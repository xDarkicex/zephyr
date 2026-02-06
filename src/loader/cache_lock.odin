package loader

import "core:sync"

// global_cache_mutex guards access to the global cache across threads.
// Tests run in parallel can otherwise race on cache init/cleanup.
global_cache_mutex: sync.Recursive_Mutex

cache_lock :: proc "contextless" () {
	sync.recursive_mutex_lock(&global_cache_mutex)
}

cache_unlock :: proc "contextless" () {
	sync.recursive_mutex_unlock(&global_cache_mutex)
}

// lock_global_cache exposes the cache lock for tests that need exclusive access.
lock_global_cache :: proc() {
	cache_lock()
}

// unlock_global_cache releases the cache lock acquired by lock_global_cache.
unlock_global_cache :: proc() {
	cache_unlock()
}

@(deferred_in=cache_unlock)
cache_guard :: proc "contextless" () -> bool {
	cache_lock()
	return true
}
