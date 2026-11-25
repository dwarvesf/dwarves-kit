// Dedicated worker for the worker.html page: opens one WebSocket to the URL the page sends and reports back.
self.onmessage = (event) => {
  let finished = false;
  const finish = () => { if (!finished) { finished = true; self.postMessage('socket settled'); } };
  try {
    const socket = new WebSocket(event.data);
    socket.onopen = finish;
    socket.onerror = finish;
    socket.onclose = finish;
  } catch (error) { finish(); }
};
