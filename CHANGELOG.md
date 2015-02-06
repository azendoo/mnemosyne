== v0.2.1 :
  * bug fixes :
    * removes request from queue when cancelled
    
== v0.2.0 :
  * enhancements :
    * remove ttl and cache expired notion
    * cache is used only when server is unreachable
  * bug fixes :
    * remove connection manager because of navigator.onLine
      value inexacte. Now rely on the fail of requests.
