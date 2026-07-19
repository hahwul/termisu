module Termisu::FFI::ErrorState
  # Per-thread last error message, in the errno style the C API expects: a caller runs an
  # operation and then reads the message back, without another thread's failure overwriting it.
  #
  # This used to be `Crystal::ThreadLocalValue`, a private stdlib type that Crystal 1.21 removed,
  # so keep a minimal equivalent here. A plain `@[ThreadLocal]` class variable is not a safe
  # substitute for a String: a value reachable *only* from thread-local storage is invisible to
  # the GC and may be collected while still in use, and the annotation is unavailable on the
  # emulated-TLS targets (Android, OpenBSD, windows-gnu). Keying a Hash on the current thread
  # keeps a strong reference and works everywhere.
  @@mutex = Mutex.new(:unchecked)
  @@last_error = {} of Thread => String

  def self.current : String
    @@mutex.synchronize { @@last_error[Thread.current]? } || ""
  end

  def self.set(message : String) : Nil
    @@mutex.synchronize { @@last_error[Thread.current] = message }
  end

  def self.clear : Nil
    # Dropping the entry and storing "" are indistinguishable through `current`; dropping it
    # also releases the message.
    @@mutex.synchronize { @@last_error.delete(Thread.current) }
  end

  def self.format(ex : Exception) : String
    msg = ex.message
    msg ? "#{ex.class.name}: #{msg}" : ex.class.name
  end
end
