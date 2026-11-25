// Small helpers shared by the hook rules.
import type {Cond} from 'gdp-wired'

// Two conditions agree: both hold or neither does (a bool has no .eq).
export const iff = (a: Cond, b: Cond): Cond => a.and(b).or(a.not().and(b.not()))

// The shape every rule module exports through index.ts.
export type LawSet = {laws: any[], stepLaws: any[], decisions?: any[], refuted?: any[], refutedSteps?: any[], helpers?: any[]}
