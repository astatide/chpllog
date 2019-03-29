use chplLogging;
use SysError;

class TooManyLocksError : Error {
  proc init() { }
}

class SpinLock {
  var l: atomic bool;
  //var log = new shared chplLogging.YggdrasilLogging();
  var log: shared chplLogging.YggdrasilLogging;
  var n: atomic int;
  var t: string;
  var writeLock: atomic int;
  var readHandles: atomic int;
  var lockLog: bool = false;

  inline proc lock(hstring: chplLogging.logHeader) throws {
    if lockLog {
      this.log.debug('locking', this.t, hstring);
    }
    while l.testAndSet(memory_order_acquire) do chpl_task_yield();
    this.n.add(1);
    if this.n.read() != 1 {
      this.log.critical('CRITICAL FAILURE: During lock, spinlock has been acquired multiple times on', this.t, hstring);
      throw new owned TooManyLocksError();
    }
    if lockLog {
      this.log.debug(this.t, 'lock successful; locks - ', this.n.read() : string, hstring);
    }
  }

  inline proc unlock(hstring: chplLogging.logHeader) throws {
    this.n.sub(1);
    if this.n.read() != 0 {
      this.log.critical('CRITICAL FAILURE: During unlock, spinlock has been acquired multiple times on', this.t, hstring);
      throw new owned TooManyLocksError();
    }
    l.clear(memory_order_release);
    if lockLog {
      this.log.debug(this.t, 'unlocked; locks - ', this.n.read() : string, hstring);
    }
  }

  // Ha, we're still using this for the logs.
  inline proc lock() {
    while l.testAndSet(memory_order_acquire) do chpl_task_yield();
  }

  inline proc unlock() {
    l.clear(memory_order_release);
  }

  inline proc rl(hstring: chplLogging.logHeader) {
    // This checks to see whether the write lock is active, and if not,
    // allows reads.
    while this.writeLock.read() >= 1 do chpl_task_yield();
    this.readHandles.add(1);
    if lockLog {
      this.log.debug('Locked RL on ', this.t : string, 'handles open -', this.readHandles.read() : string, hstring);
    }
  }

  inline proc url(hstring: chplLogging.logHeader) {
    if lockLog {
      this.log.debug('Releasing read lock on', this.t, hstring);
    }
    this.readHandles.sub(1);
    if lockLog {
      this.log.debug('Unlocked RL on ', this.t : string, 'handles open -', this.readHandles.read() : string, hstring);
    }
  }

  inline proc wl(hstring: chplLogging.logHeader) {
    // While we are actively reading, we do not write.
    if lockLog {
      this.log.debug('Requesting write lock on', this.t, 'current RL', this.readHandles.read() : string, hstring);
    }
    this.writeLock.add(1);
    while this.readHandles.read() != 0 do chpl_task_yield();
    if lockLog {
      this.log.debug('Write lock obtained on', this.t, 'current readHandles:', this.readHandles.read() : string, hstring);
    }
    this.lock(hstring);
  }

  inline proc uwl(hstring: chplLogging.logHeader) {
    this.writeLock.sub(1);
    if lockLog {
      this.log.debug('Releasing write lock on', this.t, 'current WL', this.writeLock.read() : string, hstring);
    }
    this.unlock(hstring);
  }
}
