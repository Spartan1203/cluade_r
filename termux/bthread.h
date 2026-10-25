/*
 * bthread.h shim for building R packages on Termux.
 *
 * Android's C library has no pthread cancellation. Some R packages (such as cli)
 * include <bthread.h> on Termux to get it. This shim supplies harmless stand-ins:
 * setting the cancel type/state succeeds, and pthread_cancel reports "not
 * supported", which cli already handles by leaving its timer thread running.
 *
 * Install with:
 *   curl -fsSL <url>/termux/bthread.h -o $PREFIX/include/bthread.h
 */
#ifndef RPOCKET_BTHREAD_SHIM_H
#define RPOCKET_BTHREAD_SHIM_H

#include <pthread.h>
#include <errno.h>

#ifndef PTHREAD_CANCEL_ENABLE
#define PTHREAD_CANCEL_ENABLE 0
#endif
#ifndef PTHREAD_CANCEL_DISABLE
#define PTHREAD_CANCEL_DISABLE 1
#endif
#ifndef PTHREAD_CANCEL_DEFERRED
#define PTHREAD_CANCEL_DEFERRED 0
#endif
#ifndef PTHREAD_CANCEL_ASYNCHRONOUS
#define PTHREAD_CANCEL_ASYNCHRONOUS 1
#endif

static inline int pthread_setcanceltype(int type, int *oldtype) {
  (void) type;
  if (oldtype) *oldtype = PTHREAD_CANCEL_DEFERRED;
  return 0;
}

static inline int pthread_setcancelstate(int state, int *oldstate) {
  (void) state;
  if (oldstate) *oldstate = PTHREAD_CANCEL_ENABLE;
  return 0;
}

static inline int pthread_cancel(pthread_t thread) {
  (void) thread;
  return ENOSYS;
}

static inline void pthread_testcancel(void) {}

#endif
