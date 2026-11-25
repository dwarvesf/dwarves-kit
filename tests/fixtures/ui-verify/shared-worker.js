// Shared worker for the shared-worker.html page: POSTs a JSON body to a path that answers 307 to the other port of
// the allowed host, then reports back.
self.onconnect = (event) => {
  const port = event.ports[0];
  port.onmessage = () => {
    fetch('/redirect-307', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{"shared":1}' })
      .then(() => {}, () => {})
      .then(() => port.postMessage('settled'));
  };
};
