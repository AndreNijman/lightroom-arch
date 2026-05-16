/* ntls-handshake.c - native (no-Wine) TLS handshake probe.
 * Reproduces the 32-bit nettle 4.0 bug: built -m32 it aborts inside
 * libnettle's _nettle_ecc_mod_random; built 64-bit it completes.
 * Usage: ntls-handshake <host>   (default www.microsoft.com, port 443)
 * See README.md and docs/attempt-17-cc-desktop.md. */
#include <gnutls/gnutls.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
int main(int argc,char**argv){
  const char*host=argc>1?argv[1]:"www.microsoft.com";
  gnutls_global_init();
  gnutls_session_t s; gnutls_certificate_credentials_t c;
  gnutls_certificate_allocate_credentials(&c);
  gnutls_init(&s,GNUTLS_CLIENT);
  gnutls_set_default_priority(s);
  gnutls_credentials_set(s,GNUTLS_CRD_CERTIFICATE,c);
  gnutls_server_name_set(s,GNUTLS_NAME_DNS,host,strlen(host));
  struct addrinfo hints={0},*res; hints.ai_socktype=SOCK_STREAM;
  if(getaddrinfo(host,"443",&hints,&res)){printf("dns fail\n");return 2;}
  int fd=socket(res->ai_family,SOCK_STREAM,0);
  if(connect(fd,res->ai_addr,res->ai_addrlen)){printf("connect fail\n");return 3;}
  gnutls_transport_set_int(s,fd);
  gnutls_handshake_set_timeout(s,10000);
  int r; do{r=gnutls_handshake(s);}while(r<0&&gnutls_error_is_fatal(r)==0);
  if(r<0)printf("HANDSHAKE FAIL: %s\n",gnutls_strerror(r));
  else printf("HANDSHAKE OK: %s\n",gnutls_session_get_desc(s));
  return r<0?1:0;
}
