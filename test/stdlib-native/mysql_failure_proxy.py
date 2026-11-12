"""Fault injection over real TCP; supplementary to real MySQL integration cases.

These peers exercise partial frames and blocked writes that a healthy server
cannot reliably produce on demand. They are never counted as MySQL compatibility.
"""
import contextlib, socket, threading, time
@contextlib.contextmanager
def peer(mode):
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(10)
        errors=[]
        def serve():
            try:
                with listener.accept()[0] as conn:
                    if mode=='partial_header':conn.sendall(b'\x20\x00')
                    elif mode=='partial_payload':conn.sendall(b'\x20\x00\x00\x00abc')
                    elif mode=='timeout':time.sleep(.3)
                    elif mode=='blocked_write':
                        conn.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,4096);time.sleep(1)
            except BaseException as error:errors.append(error)
        thread=threading.Thread(target=serve,daemon=True);thread.start()
        try:yield listener.getsockname()[1]
        finally:
            thread.join(10)
            if thread.is_alive():raise AssertionError('fault peer failed to finish')
            if errors:raise errors[0]

@contextlib.contextmanager
def mysql_error_proxy(upstream_port, inject_ping=False):
    """Relay a genuine MySQL session; corrupt its ERR (or PING OK) frame only."""
    import select
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0));listener.listen();listener.settimeout(10)
        errors=[]
        def serve():
            try:
                with listener.accept()[0] as client,socket.create_connection(('127.0.0.1',upstream_port),timeout=5) as server:
                    client.settimeout(5);buffers={client:bytearray(),server:bytearray()}
                    authenticated=False;ping_pending=False
                    while True:
                        readable,_,_=select.select([client,server],[],[],10)
                        if not readable:raise TimeoutError('MySQL fault relay idle')
                        for source in readable:
                            chunk=source.recv(65536)
                            if not chunk:return
                            buffers[source].extend(chunk);buffer=buffers[source]
                            while len(buffer)>=4:
                                size=int.from_bytes(buffer[:3],'little')
                                if len(buffer)<size+4:break
                                packet=bytes(buffer[:size+4]);del buffer[:size+4]
                                payload=packet[4:]
                                if source is server:
                                    corrupt=payload[:1]==b'\xff' or (inject_ping and ping_pending)
                                    if corrupt:
                                        packet=b'\x02\0\0'+packet[3:4]+b'\xff\x01';ping_pending=False
                                    elif payload[:1]==b'\0':authenticated=True
                                    client.sendall(packet)
                                else:
                                    if authenticated and payload[:1]==b'\x0e':ping_pending=True
                                    server.sendall(packet)
            except (BrokenPipeError,ConnectionResetError):pass
            except BaseException as error:errors.append(error)
        thread=threading.Thread(target=serve,daemon=True);thread.start()
        try:yield listener.getsockname()[1]
        finally:
            thread.join(12)
            if thread.is_alive():raise AssertionError('MySQL relay did not finish')
            if errors:raise errors[0]
