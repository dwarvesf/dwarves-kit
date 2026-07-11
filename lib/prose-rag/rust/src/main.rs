//! prose-rag (Rust port): semantic retrieval over my own prose.
//!
//! Same CLI contract as the Python original (index / query / hook), different engine:
//!   - static embeddings (model2vec potion-retrieval-32M): token lookup + mean +
//!     normalize, no transformer at inference. Full-corpus index is seconds on one
//!     core; the Python/ONNX version pegged ~3 cores for 8+ minutes.
//!   - incremental index: per-file FNV hash, only changed/new files re-embed
//!   - single static binary, ~ms startup (the Python hook paid ~250ms interpreter+model tax)
//!
//! Index lives at ~/.claude/prose-rag/index.bin (bincode; the Python index.db is untouched).
//! NOTE: sim floors differ from the bge-small originals (different model, different
//! score distribution); defaults below were recalibrated against the real corpus.

use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::Read;
use std::path::{Path, PathBuf};

const MODEL_ID: &str = "minishlab/potion-retrieval-32M";
// Pinned upstream revision: floors and retrieval quality are calibrated against this
// exact table, and an unpinned `main` lets a compromised/updated upstream silently swap
// the model. Re-pin deliberately (and re-run the proof-of-done B3/B4 checks) to upgrade.
const MODEL_REV: &str = "6fc8051fab2a1e0ee76689cf08c853792ac285e7";
const CHUNK_MAX: usize = 1500; // chars embedded per chunk (parity with Python)
const CHUNK_MIN: usize = 40; // skip chunks shorter than this

// Precision-biased recall markers (ported verbatim): only these phrasings pass the
// hook gate, so operational prompts (edits, git, "fix this") cost ~0.
const RECALL_MARKERS: &[&str] = &[
    "have i ",
    "have we ",
    "did i ",
    "did we ",
    "didn't i",
    "didn't we",
    "what did i",
    "what did we",
    "what do my notes",
    "do i have notes",
    "did i already",
    "already solved",
    "already figure",
    "search my notes",
    "my notes on",
    "wrote about",
    "noted about",
    "what did i conclude",
    "have i written",
    "have i covered",
    "conclude about",
    "didn't we already",
];

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME not set"))
}

fn default_db() -> PathBuf {
    std::env::var("PROSE_RAG_DB")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home().join(".claude/prose-rag/index.bin"))
}

// Corpus is consumer config (adapter-default invariant: no personal path baked in).
// PROSE_RAG_CORPUS is colon-separated dirs/files; "~/" expands to $HOME.
fn default_corpus() -> Vec<PathBuf> {
    let h = home();
    std::env::var("PROSE_RAG_CORPUS")
        .unwrap_or_default()
        .split(':')
        .filter(|p| !p.is_empty())
        .map(|p| {
            if let Some(rest) = p.strip_prefix("~/") {
                h.join(rest)
            } else {
                PathBuf::from(p)
            }
        })
        .filter(|p| p.exists())
        .collect()
}

// FNV-1a 64: stable across builds (std's DefaultHasher is not), 6 lines, good enough
// for change detection on trusted local files.
fn fnv1a(data: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for &b in data {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

// index format

#[derive(Serialize, Deserialize, Debug, PartialEq)]
struct ChunkRec {
    heading: String,
    text: String,
    vec: Vec<f32>, // L2-normalized, so cosine == dot
}

#[derive(Serialize, Deserialize, Debug, PartialEq)]
struct FileRec {
    hash: u64,
    source: String, // display path, parity with Python's relpath convention
    chunks: Vec<ChunkRec>,
}

#[derive(Serialize, Deserialize, Debug, PartialEq, Default)]
struct Index {
    model: String,
    files: HashMap<String, FileRec>, // key: absolute file path
}

/// Missing or empty file = "no index yet". A NON-EMPTY file that fails to deserialize is
/// an error, never silently an empty index: the likely cause is PROSE_RAG_DB pointing at
/// the legacy Python index.db (sqlite), and defaulting would let `index` clobber it.
fn load_index(db: &Path) -> Result<Index> {
    let bytes = match std::fs::read(db) {
        Ok(b) => b,
        Err(_) => return Ok(Index::default()),
    };
    if bytes.is_empty() {
        return Ok(Index::default());
    }
    bincode::deserialize(&bytes).map_err(|_| {
        anyhow!(
            "{} exists but is not a prose-rag Rust index (PROSE_RAG_DB pointing at the \
             legacy Python index.db?); refusing to touch it. Delete it, point --db \
             elsewhere, or pass --full to rebuild over it deliberately.",
            db.display()
        )
    })
}

fn save_index(db: &Path, idx: &Index) -> Result<()> {
    if let Some(dir) = db.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = db.with_extension("bin.tmp");
    std::fs::write(&tmp, bincode::serialize(idx)?)?;
    // the index holds full private note text; keep it owner-only
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600))?;
    }
    std::fs::rename(&tmp, db)?;
    Ok(())
}

// chunking (parity with the Python chunker)

/// Split a markdown doc into heading-anchored (#, ##, ###) chunks. No headings -> one chunk.
fn chunk_markdown(text: &str) -> Vec<(String, String)> {
    let text = text.trim();
    if text.is_empty() {
        return vec![];
    }
    // Byte offsets where a heading line starts.
    let mut starts: Vec<usize> = vec![];
    let mut pos = 0;
    for line in text.split_inclusive('\n') {
        let t = line.trim_start_matches('#');
        let hashes = line.len() - t.len();
        if (1..=3).contains(&hashes) && t.starts_with(' ') {
            starts.push(pos);
        }
        pos += line.len();
    }
    if starts.first() != Some(&0) {
        starts.insert(0, 0);
    }
    let mut out = vec![];
    for (i, &s) in starts.iter().enumerate() {
        let e = starts.get(i + 1).copied().unwrap_or(text.len());
        let span = text[s..e].trim();
        if span.chars().count() < CHUNK_MIN {
            continue;
        }
        let first = span.lines().next().unwrap_or("");
        let heading: String = first
            .trim_start_matches('#')
            .trim()
            .chars()
            .take(120)
            .collect();
        if span.chars().count() <= CHUNK_MAX {
            out.push((heading, span.to_string()));
            continue;
        }
        // Window long spans on line boundaries instead of truncating (parity with the
        // Python fix in #768): a section longer than CHUNK_MAX (e.g. a big table)
        // would otherwise lose everything past the first CHUNK_MAX chars.
        let mut buf = String::new();
        for ln in span.split_inclusive('\n') {
            if !buf.is_empty() && buf.chars().count() + ln.chars().count() > CHUNK_MAX {
                if buf.trim().chars().count() >= CHUNK_MIN {
                    out.push((heading.clone(), buf.trim().to_string()));
                }
                buf.clear();
            }
            buf.push_str(ln);
        }
        if buf.trim().chars().count() >= CHUNK_MIN {
            out.push((heading, buf.trim().to_string()));
        }
    }
    out
}

/// Collect every .md file (skipping dot-dirs) plus its display source, per corpus entry.
fn gather_files(corpus: &[PathBuf]) -> Vec<(PathBuf, String)> {
    let mut out = vec![];
    for root in corpus {
        if root.is_file() && root.extension().is_some_and(|e| e == "md") {
            let src = root.file_name().unwrap().to_string_lossy().into_owned();
            out.push((root.clone(), src));
        } else if root.is_dir() {
            // Python parity: source is relative to the corpus root's PARENT ("til/x.md").
            let base = root.parent().unwrap_or(root);
            let mut stack = vec![root.clone()];
            while let Some(dir) = stack.pop() {
                let Ok(entries) = std::fs::read_dir(&dir) else {
                    continue;
                };
                for e in entries.flatten() {
                    let p = e.path();
                    let name = e.file_name().to_string_lossy().into_owned();
                    if name.starts_with('.') {
                        continue;
                    }
                    // file_type() (not is_dir()) so symlinked dirs are NOT followed:
                    // a cycle would loop forever, and a link out of the corpus would
                    // silently index foreign files. Matches Python os.walk defaults.
                    let is_dir = e.file_type().map(|t| t.is_dir()).unwrap_or(false);
                    if is_dir {
                        stack.push(p);
                    } else if p.extension().is_some_and(|x| x == "md") {
                        let src = p
                            .strip_prefix(base)
                            .unwrap_or(&p)
                            .to_string_lossy()
                            .into_owned();
                        out.push((p, src));
                    }
                }
            }
        }
    }
    out
}

// embedder (model2vec static embeddings)

struct Embedder {
    tokenizer: tokenizers::Tokenizer,
    // mmap'd model.safetensors: rows are converted on lookup, so a hook/query call
    // touches only the ~dozens of token rows it needs instead of eagerly converting
    // the whole 123MB table (which cost ~500ms per invocation).
    mmap: memmap2::Mmap,
    data_off: usize, // byte offset of the table within the mmap
    f16: bool,
    vocab: usize,
    dim: usize,
}

impl Embedder {
    /// `allow_download: false` = cache-only (the hook path: a UserPromptSubmit hook must
    /// never stall a prompt on a ~123MB network download; it silently skips instead).
    fn load(allow_download: bool) -> Result<Self> {
        // Cache-first: hf-hub's online get() does a network etag check per file even
        // when cached (~450ms), which would eat the hook's latency budget every prompt.
        // Revision pinned (MODEL_REV): floors are calibrated to this exact table.
        let rev_repo = || {
            hf_hub::Repo::with_revision(
                MODEL_ID.to_string(),
                hf_hub::RepoType::Model,
                MODEL_REV.to_string(),
            )
        };
        let cache_repo = hf_hub::Cache::default().repo(rev_repo());
        let (tok_p, weights_p) = match (
            cache_repo.get("tokenizer.json"),
            cache_repo.get("model.safetensors"),
        ) {
            (Some(t), Some(w)) => (t, w),
            _ if !allow_download => {
                bail!("model not in the hf cache; run `prose-rag index` once to fetch it")
            }
            _ => {
                let repo = hf_hub::api::sync::Api::new()?.repo(rev_repo());
                (
                    repo.get("tokenizer.json")
                        .context("download tokenizer.json")?,
                    repo.get("model.safetensors")
                        .context("download model.safetensors")?,
                )
            }
        };

        let tokenizer = tokenizers::Tokenizer::from_file(tok_p).map_err(|e| anyhow!("{e}"))?;
        // model2vec ships one 2-D tensor: the token-embedding table. mmap it and
        // record the table's offset/shape; rows convert lazily in embed().
        let file = std::fs::File::open(&weights_p)?;
        let mmap = unsafe { memmap2::Mmap::map(&file)? };
        let st = safetensors::SafeTensors::deserialize(&mmap)?;
        let name = st
            .names()
            .into_iter()
            .find(|n| st.tensor(n).map(|t| t.shape().len() == 2).unwrap_or(false))
            .ok_or_else(|| anyhow!("no 2-D tensor in {MODEL_ID} safetensors"))?;
        let t = st.tensor(name)?;
        let (vocab, dim) = (t.shape()[0], t.shape()[1]);
        let f16 = match t.dtype() {
            safetensors::Dtype::F32 => false,
            safetensors::Dtype::F16 => true,
            d => bail!("unsupported dtype {d:?} in {MODEL_ID}"),
        };
        let data_off = t.data().as_ptr() as usize - mmap.as_ptr() as usize;
        Ok(Self {
            tokenizer,
            mmap,
            data_off,
            f16,
            vocab,
            dim,
        })
    }

    /// Accumulate token row `id` into `v` (lazy dtype conversion off the mmap).
    fn add_row(&self, id: usize, v: &mut [f32]) {
        let esz = if self.f16 { 2 } else { 4 };
        let start = self.data_off + id * self.dim * esz;
        let row = &self.mmap[start..start + self.dim * esz];
        if self.f16 {
            for (a, b) in v.iter_mut().zip(row.chunks_exact(2)) {
                *a += half::f16::from_le_bytes([b[0], b[1]]).to_f32();
            }
        } else {
            for (a, b) in v.iter_mut().zip(row.chunks_exact(4)) {
                *a += f32::from_le_bytes([b[0], b[1], b[2], b[3]]);
            }
        }
    }

    /// Embed texts: token lookup + mean + L2 normalize (model2vec inference).
    fn embed(&self, texts: &[&str]) -> Result<Vec<Vec<f32>>> {
        texts
            .iter()
            .map(|text| {
                let enc = self
                    .tokenizer
                    .encode(*text, false) // no special tokens: the table has none
                    .map_err(|e| anyhow!("{e}"))?;
                let mut v = vec![0f32; self.dim];
                let mut n = 0usize;
                for &id in enc.get_ids() {
                    let id = id as usize;
                    if id >= self.vocab {
                        continue;
                    }
                    self.add_row(id, &mut v);
                    n += 1;
                }
                if n > 0 {
                    let inv = 1.0 / n as f32;
                    for a in v.iter_mut() {
                        *a *= inv;
                    }
                }
                let norm = v.iter().map(|x| x * x).sum::<f32>().sqrt();
                if norm > 0.0 {
                    for a in v.iter_mut() {
                        *a /= norm;
                    }
                }
                Ok(v)
            })
            .collect()
    }
}

// commands

fn cmd_index(corpus: Vec<PathBuf>, db: &Path, full: bool) -> Result<i32> {
    let corpus = if corpus.is_empty() {
        default_corpus()
    } else {
        corpus
    };
    let files = gather_files(&corpus);
    if files.is_empty() {
        eprintln!("prose-rag: no markdown files found in corpus");
        return Ok(1);
    }

    let mut idx = if full {
        Index::default() // explicit rebuild consent: --full may overwrite a foreign file
    } else {
        load_index(db)?
    };
    if idx.model != MODEL_ID {
        idx = Index::default(); // model changed -> vectors incompatible, full rebuild
    }
    idx.model = MODEL_ID.to_string();

    // Diff pass: what changed / vanished since last index.
    let mut seen: HashMap<String, ()> = HashMap::new();
    // (path, source, hash, chunks)
    type Todo = (String, String, u64, Vec<(String, String)>);
    let mut todo: Vec<Todo> = vec![];
    for (path, source) in &files {
        let key = path.to_string_lossy().into_owned();
        seen.insert(key.clone(), ());
        let Ok(bytes) = std::fs::read(path) else {
            continue;
        };
        let hash = fnv1a(&bytes);
        if idx.files.get(&key).is_some_and(|f| f.hash == hash) {
            continue; // unchanged: keep existing vectors
        }
        let text = String::from_utf8_lossy(&bytes);
        todo.push((key, source.clone(), hash, chunk_markdown(&text)));
    }
    let removed: Vec<String> = idx
        .files
        .keys()
        .filter(|k| !seen.contains_key(*k))
        .cloned()
        .collect();
    for k in &removed {
        idx.files.remove(k);
    }

    let n_chunks: usize = todo.iter().map(|t| t.3.len()).sum();
    if n_chunks == 0 && removed.is_empty() {
        eprintln!("prose-rag: index up to date ({} files)", files.len());
        return Ok(0);
    }
    eprintln!(
        "prose-rag: embedding {} chunks from {} changed files ({} removed, {} total files)...",
        n_chunks,
        todo.len(),
        removed.len(),
        files.len()
    );

    if n_chunks > 0 {
        let emb = Embedder::load(true)?;
        let texts: Vec<&str> = todo
            .iter()
            .flat_map(|t| t.3.iter().map(|c| c.1.as_str()))
            .collect();
        let mut vecs = emb.embed(&texts)?.into_iter();
        for (key, source, hash, chunks) in todo {
            let recs = chunks
                .into_iter()
                .map(|(heading, text)| ChunkRec {
                    heading,
                    text,
                    vec: vecs.next().unwrap(),
                })
                .collect();
            idx.files.insert(
                key,
                FileRec {
                    hash,
                    source,
                    chunks: recs,
                },
            );
        }
    }

    save_index(db, &idx)?;
    let total: usize = idx.files.values().map(|f| f.chunks.len()).sum();
    eprintln!(
        "prose-rag: indexed {} chunks ({} files) -> {}",
        total,
        idx.files.len(),
        db.display()
    );
    Ok(0)
}

struct Hit<'a> {
    source: &'a str,
    heading: &'a str,
    sim: f32,
}

fn format_hit(h: &Hit) -> String {
    if h.heading.is_empty() {
        h.source.to_string()
    } else {
        format!("{} :: {}", h.source, h.heading)
    }
}

fn search<'a>(idx: &'a Index, query_vec: &[f32], k: usize, floor: f32) -> Vec<Hit<'a>> {
    let mut hits: Vec<Hit> = vec![];
    for f in idx.files.values() {
        for c in &f.chunks {
            // vectors are L2-normalized: cosine == dot
            let sim: f32 = c.vec.iter().zip(query_vec).map(|(a, b)| a * b).sum();
            if sim >= floor {
                hits.push(Hit {
                    source: &f.source,
                    heading: &c.heading,
                    sim,
                });
            }
        }
    }
    hits.sort_by(|a, b| {
        b.sim
            .partial_cmp(&a.sim)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    hits.truncate(k);
    hits
}

fn cmd_query(text: &str, db: &Path, k: usize, floor: f32, json: bool) -> Result<i32> {
    let idx = load_index(db)?;
    if idx.files.is_empty() {
        eprintln!(
            "prose-rag: no index at {}; run `prose-rag index` first",
            db.display()
        );
        return Ok(1);
    }
    let emb = Embedder::load(true)?;
    let qv = emb.embed(&[text])?.remove(0);
    let hits = search(&idx, &qv, k, floor);
    if json {
        let arr: Vec<_> = hits
            .iter()
            .map(|h| serde_json::json!({"source": h.source, "heading": h.heading, "sim": (h.sim * 1000.0).round() / 1000.0}))
            .collect();
        println!("{}", serde_json::to_string_pretty(&arr)?);
        return Ok(0);
    }
    if hits.is_empty() {
        println!("(no matches above floor)");
        return Ok(0);
    }
    for h in &hits {
        println!("[{:.2}] {}", h.sim, format_hit(h));
    }
    Ok(0)
}

fn looks_like_recall(prompt: &str) -> bool {
    let low = prompt.to_lowercase();
    RECALL_MARKERS.iter().any(|m| low.contains(m))
}

fn cmd_hook(db: &Path, k: usize, floor: f32, force: bool, no_gate: bool) -> Result<i32> {
    if std::env::var("PROSE_RAG_INJECT").as_deref() != Ok("1") && !force {
        return Ok(0);
    }
    let mut buf = String::new();
    if std::io::stdin().read_to_string(&mut buf).is_err() {
        return Ok(0);
    }
    let Ok(payload) = serde_json::from_str::<serde_json::Value>(&buf) else {
        return Ok(0);
    };
    let prompt = payload
        .get("prompt")
        .or_else(|| payload.get("lastPrompt"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if prompt.trim().is_empty() {
        return Ok(0);
    }
    let gate_off = no_gate || std::env::var("PROSE_RAG_NO_GATE").as_deref() == Ok("1");
    if !gate_off && !looks_like_recall(prompt) {
        return Ok(0);
    }
    // hook contract: NEVER noise a prompt. Any load problem (foreign db file, model not
    // cached) means silently skip; the user finds out via query/index, not mid-prompt.
    let Ok(idx) = load_index(db) else {
        return Ok(0);
    };
    if idx.files.is_empty() {
        return Ok(0);
    }
    let Ok(emb) = Embedder::load(false) else {
        return Ok(0);
    };
    let qv = emb.embed(&[prompt])?.remove(0);
    let hits = search(&idx, &qv, k, floor);
    if hits.is_empty() {
        return Ok(0);
    }
    let mut lines = vec!["Relevant prior notes (prose-rag, may help, may not):".to_string()];
    for h in &hits {
        lines.push(format!("- {} (sim {:.2})", format_hit(h), h.sim));
    }
    println!("{}", lines.join("\n"));
    Ok(0)
}

// arg parsing (hand-rolled: 3 subcommands, a handful of flags)

fn usage() -> ! {
    eprintln!("usage: prose-rag index [--corpus PATH]... [--db PATH] [--full]");
    eprintln!("       prose-rag query <text> [--db PATH] [--k N] [--floor F] [--json]");
    eprintln!("       prose-rag hook  [--db PATH] [--k N] [--floor F] [--force] [--no-gate]");
    std::process::exit(2);
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(cmd) = args.first() else { usage() };

    let mut db = default_db();
    let mut corpus: Vec<PathBuf> = vec![];
    let mut k: Option<usize> = None;
    let mut floor: Option<f32> = None;
    let (mut json, mut full, mut force, mut no_gate) = (false, false, false, false);
    let mut positional: Vec<String> = vec![];

    let mut it = args[1..].iter();
    while let Some(a) = it.next() {
        let mut val = |name: &str| -> String {
            it.next()
                .unwrap_or_else(|| {
                    eprintln!("missing value for {name}");
                    usage()
                })
                .clone()
        };
        match a.as_str() {
            "--db" => db = PathBuf::from(val("--db")),
            "--corpus" => corpus.push(PathBuf::from(val("--corpus"))),
            "--k" => k = Some(val("--k").parse().context("--k")?),
            "--floor" => floor = Some(val("--floor").parse().context("--floor")?),
            "--json" => json = true,
            "--full" => full = true,
            "--force" => force = true,
            "--no-gate" => no_gate = true,
            "--help" | "-h" => usage(),
            _ if a.starts_with("--") => {
                eprintln!("unknown flag {a}");
                usage()
            }
            _ => positional.push(a.clone()),
        }
    }

    let code = match cmd.as_str() {
        "index" => cmd_index(corpus, &db, full)?,
        "query" => {
            let Some(text) = positional.first() else {
                usage()
            };
            // floors recalibrated for potion-retrieval-32M (noise <=0.26, real 0.41-0.58;
            // the bge originals were 0.55/0.62)
            cmd_query(text, &db, k.unwrap_or(5), floor.unwrap_or(0.32), json)?
        }
        "hook" => cmd_hook(&db, k.unwrap_or(4), floor.unwrap_or(0.40), force, no_gate)?,
        _ => usage(),
    };
    if code != 0 {
        bail!("exit {code}");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunker_matches_python_shape() {
        let md = "# Title\n\nintro text long enough to pass the minimum length gate here\n\n## Section two\n\nmore body text that is also long enough to pass the minimum gate";
        let chunks = chunk_markdown(md);
        assert_eq!(chunks.len(), 2);
        assert_eq!(chunks[0].0, "Title");
        assert_eq!(chunks[1].0, "Section two");
        // no headings -> one chunk
        let plain =
            chunk_markdown("just a plain paragraph with no headings but long enough to keep");
        assert_eq!(plain.len(), 1);
        // short chunks dropped
        assert!(chunk_markdown("# Hi\n\ntiny").is_empty());
    }

    #[test]
    fn chunker_windows_long_sections() {
        // one heading, body far over CHUNK_MAX: must window, not truncate
        let line = "a line of table-ish content that repeats to exceed the chunk cap |\n";
        let md = format!("# Big\n\n{}", line.repeat(60)); // ~4000 chars
        let chunks = chunk_markdown(&md);
        assert!(chunks.len() >= 3, "expected windows, got {}", chunks.len());
        assert!(chunks.iter().all(|c| c.0 == "Big")); // heading carried to every window
        assert!(chunks.iter().all(|c| c.1.chars().count() <= CHUNK_MAX));
        // no content lost: total windowed chars ~ input body size
        let total: usize = chunks.iter().map(|c| c.1.chars().count()).sum();
        assert!(total > 3500, "content lost: only {total} chars kept");
    }

    // merged from the sibling port of the same fix (#772): complementary assertions
    // (tail-marker retrievability + short-doc regression guard)
    #[test]
    fn long_section_windows_instead_of_truncating() {
        // One heading + ~40 table rows (~4000 chars), marker in the LAST row.
        // The pre-fix chunker kept only the first CHUNK_MAX chars (the
        // VERDICTS.md bug: mid-table verdicts unsearchable).
        let mut md = String::from("# Big ledger\n\n| date | subject | verdict |\n|---|---|---|\n");
        for i in 0..39 {
            md.push_str(&format!(
                "| 2026-01-{:02} | subject number {} with padding text to lengthen the row | GO |\n",
                i % 28 + 1,
                i
            ));
        }
        md.push_str("| 2026-02-01 | zzquokka final row marker | NO-GO |\n");
        let chunks = chunk_markdown(&md);
        assert!(
            chunks.len() >= 3,
            "expected windowing, got {} chunk(s)",
            chunks.len()
        );
        assert!(chunks.iter().all(|(h, _)| h == "Big ledger"));
        assert!(chunks.iter().all(|(_, t)| t.chars().count() <= CHUNK_MAX));
        let joined: String = chunks.iter().map(|(_, t)| t.as_str()).collect();
        assert!(joined.contains("zzquokka"), "tail row lost");
        // short docs still one chunk (regression guard)
        let short = chunk_markdown("# T\n\nshort body over forty characters to pass the gate ok");
        assert_eq!(short.len(), 1);
    }

    #[test]
    fn fnv_stable() {
        assert_eq!(fnv1a(b"hello"), 0xa430d84680aabd0b);
        assert_ne!(fnv1a(b"hello"), fnv1a(b"hello "));
    }

    #[test]
    fn recall_gate() {
        assert!(looks_like_recall("Have I written about sqlite-vec?"));
        assert!(!looks_like_recall("fix the bug in main.rs"));
    }

    #[test]
    fn search_ranks_by_dot() {
        let mut idx = Index::default();
        idx.files.insert(
            "a".into(),
            FileRec {
                hash: 1,
                source: "a.md".into(),
                chunks: vec![
                    ChunkRec {
                        heading: "hi".into(),
                        text: "t".into(),
                        vec: vec![1.0, 0.0],
                    },
                    ChunkRec {
                        heading: "lo".into(),
                        text: "t".into(),
                        vec: vec![0.6, 0.8],
                    },
                ],
            },
        );
        let hits = search(&idx, &[1.0, 0.0], 5, 0.5);
        assert_eq!(hits.len(), 2);
        assert_eq!(hits[0].heading, "hi");
        assert!(hits[0].sim > hits[1].sim);
    }

    fn tmp_path(tag: &str) -> PathBuf {
        std::env::temp_dir().join(format!("prose-rag-test-{}-{}", std::process::id(), tag))
    }

    #[test]
    fn chunker_boundary_and_remainder() {
        // exactly CHUNK_MAX chars after trim: single chunk, no windowing
        let body = "x".repeat(CHUNK_MAX - 8); // "# B\n\n" + body trims to exactly CHUNK_MAX? build precisely:
        let md = format!("# B\n\n{body}");
        let span_len = md.trim().chars().count();
        assert!(span_len <= CHUNK_MAX);
        assert_eq!(chunk_markdown(&md).len(), 1);
        // just over: windows into 2+
        let md_over = format!("# B\n\n{}\n{}", "x".repeat(CHUNK_MAX - 10), "y".repeat(50));
        let chunks = chunk_markdown(&md_over);
        assert!(chunks.len() >= 2, "expected windowing past CHUNK_MAX");
        // documented behavior: a trailing remainder under CHUNK_MIN is DROPPED (parity
        // with the Python chunker), so tiny tail fragments do not become noise chunks
        let md_tail = format!("# B\n\n{}\ntiny", "z".repeat(CHUNK_MAX - 6));
        let chunks = chunk_markdown(&md_tail);
        assert!(
            chunks.iter().all(|c| c.1.chars().count() >= CHUNK_MIN),
            "sub-CHUNK_MIN remainder must be dropped, not emitted"
        );
    }

    #[test]
    fn index_roundtrip_and_corruption() {
        let mut idx = Index::default();
        idx.model = MODEL_ID.into();
        idx.files.insert(
            "/tmp/a.md".into(),
            FileRec {
                hash: 42,
                source: "a.md".into(),
                chunks: vec![ChunkRec {
                    heading: "h".into(),
                    text: "body".into(),
                    vec: vec![0.5; 4],
                }],
            },
        );
        let p = tmp_path("roundtrip.bin");
        save_index(&p, &idx).unwrap();
        assert_eq!(load_index(&p).unwrap(), idx); // full fidelity
                                                  // missing file = fresh index
        assert_eq!(
            load_index(&tmp_path("missing.bin")).unwrap(),
            Index::default()
        );
        // empty file = fresh index
        let e = tmp_path("empty.bin");
        std::fs::write(&e, b"").unwrap();
        assert_eq!(load_index(&e).unwrap(), Index::default());
        // NON-EMPTY foreign/corrupt file = loud error, never silently empty (the
        // PROSE_RAG_DB-pointed-at-index.db clobber guard)
        let c = tmp_path("corrupt.bin");
        std::fs::write(&c, b"SQLite format 3\0not-bincode").unwrap();
        assert!(load_index(&c).is_err());
    }

    #[test]
    fn gather_files_source_naming_parity() {
        let root = tmp_path("corpus");
        let sub = root.join("sub");
        std::fs::create_dir_all(&sub).unwrap();
        std::fs::write(root.join("b.md"), "content").unwrap();
        std::fs::write(sub.join("a.md"), "content").unwrap();
        std::fs::write(root.join("skip.txt"), "content").unwrap();
        let mut files = gather_files(&[root.clone()]);
        files.sort();
        let corpus_name = root.file_name().unwrap().to_string_lossy();
        let sources: Vec<&str> = files.iter().map(|(_, s)| s.as_str()).collect();
        // Python parity: source is relative to the corpus root's PARENT
        assert_eq!(
            sources,
            vec![
                format!("{corpus_name}/b.md"),
                format!("{corpus_name}/sub/a.md")
            ]
        );
        // single-file corpus entry: source is the basename
        let single = gather_files(&[root.join("b.md")]);
        assert_eq!(single[0].1, "b.md");
        // symlinked dir is NOT followed (cycle/escape guard)
        #[cfg(unix)]
        {
            let loop_link = root.join("loop");
            if std::os::unix::fs::symlink(&root, &loop_link).is_ok() {
                let walked = gather_files(&[root.clone()]); // must terminate
                assert_eq!(walked.len(), 2, "symlink dir followed: corpus escaped");
            }
        }
    }

    #[test]
    fn embedder_decode_rows_f32_and_f16() {
        // Build a synthetic 2x4 table in real safetensors format and drive add_row
        // through the same mmap path production uses. Tokenizer is required by the
        // struct but untouched by add_row; a minimal WordLevel stub satisfies it.
        fn synthetic(dtype: &str, data: Vec<u8>, tag: &str) -> Embedder {
            let header = format!(
                "{{\"table\":{{\"dtype\":\"{dtype}\",\"shape\":[2,4],\"data_offsets\":[0,{}]}}}}",
                data.len()
            );
            let mut bytes = (header.len() as u64).to_le_bytes().to_vec();
            bytes.extend_from_slice(header.as_bytes());
            bytes.extend_from_slice(&data);
            let p = tmp_path(tag);
            std::fs::write(&p, &bytes).unwrap();
            let file = std::fs::File::open(&p).unwrap();
            let mmap = unsafe { memmap2::Mmap::map(&file).unwrap() };
            let st = safetensors::SafeTensors::deserialize(&mmap).unwrap();
            let data_off =
                st.tensor("table").unwrap().data().as_ptr() as usize - mmap.as_ptr() as usize;
            let f16 = dtype == "F16";
            Embedder {
                tokenizer: tokenizers::Tokenizer::new(
                    tokenizers::models::wordlevel::WordLevel::default(),
                ),
                mmap,
                data_off,
                f16,
                vocab: 2,
                dim: 4,
            }
        }
        // f32 rows: [1,2,3,4], [5,6,7,8]
        let f32_bytes: Vec<u8> = (1..=8).flat_map(|i| (i as f32).to_le_bytes()).collect();
        let emb = synthetic("F32", f32_bytes, "st-f32");
        let mut v = vec![0f32; 4];
        emb.add_row(1, &mut v);
        assert_eq!(v, vec![5.0, 6.0, 7.0, 8.0]);
        emb.add_row(0, &mut v); // accumulates
        assert_eq!(v, vec![6.0, 8.0, 10.0, 12.0]);
        // f16 rows, same values
        let f16_bytes: Vec<u8> = (1..=8)
            .flat_map(|i| half::f16::from_f32(i as f32).to_le_bytes())
            .collect();
        let emb = synthetic("F16", f16_bytes, "st-f16");
        let mut v = vec![0f32; 4];
        emb.add_row(0, &mut v);
        assert_eq!(v, vec![1.0, 2.0, 3.0, 4.0]);
    }
}
