/* Documentation for chplLogging */

config const flushToLog: bool = false;
config const stdoutOnly: bool = false;

module chplLogging {
  writeln("New library: chplLogging");

  use spinlock;
  use IO;
  use Time;

  record yggHeader {
    // How many levels of the stack to report?
    var levels: int = 10;
    // if we set it to zero, we should print FOREVER.  Not really, just the full
    // stack.  Actually, that's really not true.  Oh well.
    var m: domain(int);
    var msg: [m] string;
    var sep: string = '//';
    // Given to us by the Valkyries above.
    var id: string = 'stdout';
    var sendTo: string;
    var currentTask: int;
    // header should actually be sendTo
    var header: string;
    var time: string;
    var printedHeader: bool = false;
    var useTime: bool = true;

    proc writeThis(wc) {
      // this is function to allow this to be written directly.
      //
      var spaces: int;
      if !printedHeader {
        wc.writeln('');
        wc.write(' '*6);
        if this.m.size > this.levels {
          wc.write('..', this.sep);
          for i in this.m.size-levels+1..this.m.size {
            wc.write(this.msg[i], this.sep);
          }
        } else {
          for i in 1..this.m.size {
            wc.write(this.msg[i], this.sep);
          }
        }
        wc.writeln('');
        if this.useTime {
          spaces = 15;
        } else {
          spaces = 6;
        }
        this.printedHeader = true;
        //wc.write(this.time, ' - ');
      } else {
        if this.useTime {
          spaces = 9;
        } else {
          spaces = 6;
        }
      }
      wc.write(' '*spaces);
      if this.useTime {
        wc.write(this.time, ' - ');
      }
    }

    proc path() {
      // this is function to allow this to be written directly.
      var msg: string;
      if this.m.size > this.levels {
        for i in this.m.size-levels+1..this.m.size {
          msg += this.msg[i] + this.sep;
        }
      } else {
        for i in 1..this.m.size {
          msg += this.msg[i] + this.sep;
        }
      }
      return msg;
    }

    proc size {
      var tm: int;
      tm += this.time.size+1;
      if !printedHeader {
        if this.m.size > this.levels {
          for i in this.m.size-levels..this.m.size {
            tm += this.msg[i].size + this.sep.size;
          }
        } else {
          for i in 1..this.m.size {
            tm += this.msg[i].size + this.sep.size;
          }
        }
      } else {
        tm = 15;
      }
      return tm+1;
    }
  }

  proc +(a: yggHeader, b: string) {
    var y = new yggHeader();
    for i in 1..a.m.size {
      y.m.add(i);
      y.msg[i] = a.msg[i];
    }
    y.m.add(a.m.size+1);
    y.msg[a.m.size+1] = b;
    y.id = a.id;
    y.header = a.header;
    y.currentTask = a.currentTask;
    y.levels = a.levels;
    y.sep = a.sep;
    y.printedHeader = a.printedHeader;
    return y;
  }

  proc +(b: string, a: yggHeader) {
    var y = new yggHeader();
    for i in 1..a.m.size {
      y.m.add(i);
      y.msg[i] = a.msg[i];
    }
    y.m.add(a.m.size+1);
    y.msg[a.m.size+1] = b;
    y.id = a.id;
    y.header = a.header;
    y.currentTask = a.currentTask;
    y.levels = a.levels;
    y.sep = a.sep;
    y.printedHeader = a.printedHeader;
    return y;
  }

  proc +=(ref a: yggHeader, b: string) {
    a.m.add(a.m.size+1);
    a.msg[a.m.size+1] = b;
  }

  class YggdrasilLogging {
    // This is a class to let us handle all input and output.
    var currentDebugLevel: int;
    var DEVEL = -1;
    var DEBUG = 0;
    var WARNING = 1;
    var RUNTIME = 2;
    var maxCharacters = 160;
    var headerLiner = '_';
    var headerStarter = '/';
    var indent = 5;
    var l = new shared spinlock.SpinLock();
    var tId: int;
    //var wc: channel;
    var filesOpened: domain(string);
    var channelsOpened: [filesOpened] channel(true,iokind.dynamic,true);
    var channelDebugHeader: [filesOpened] string;
    var channelDebugPath: [filesOpened] string;
    var fileHandles: [filesOpened] file;
    var lastDebugHeader = '';
    var time = Time.getCurrentTime();
    //var l: [filesOpened] spinlock.SpinLock;

    proc init() {
      //this.filesOpened = new domain(string);
      //this.channelsOpened = [filesOpened] channel(true,iokind.dynamic,true);
      //this.filesOpened.add('stdout');
      //this.channelsOpened['stdout'] = stdout;
    }

    proc exitRoutine() throws {
      for id in this.filesOpened {
        //this.channelsOpened[id].commit();
        //writeln(this.fileHandles[id] : string);
        try {
          this.channelsOpened[id].writeln('EXCEPTION CAUGHT');
          this.channelsOpened[id].close();
          this.fileHandles[id].fsync();
        } catch {
          // And then do nothing.
        }
      }
    }

    proc formatHeader(mtype: string) {
      // Formats a header for us to print out to stdout.
      var header = ' '.join(this.headerStarter*5, mtype, this.headerStarter);
      var nToEnd = this.maxCharacters - header.size;
      header = header + (this.headerStarter*nToEnd);
      return header;
    }

    proc printToConsole(msg, debugLevel: string, hstring: yggHeader, header: bool) throws {
      // check whether we're going to stdout or not.
      var wc = stdout;
      var useStdout: bool = true;
      var vstring = hstring;
      var lf: file;
      var lastDebugHeader: string;
      l.lock();
      var id: string;

      if this.lastDebugHeader == '' {
        if !this.filesOpened.contains('stdout') {
          this.filesOpened.add('stdout');
          var lf = open('EVOCAP.log', iomode.cw);
          this.fileHandles['stdout'] = lf;
          this.channelsOpened['stdout'] = lf.writer();
        }
      }

      if hstring.header == 'VALKYRIE' {
        id = hstring.id;
        // First, check to see whether we've created the file.
        if this.filesOpened.contains(id) {
          if flushToLog {
            // if we're in debug mode, we close the channels.
            // Otherwise, we leave them open.  It's for exception handling.
            try {
              // yay segfault?
              lf = this.fileHandles[id];
              var fileSize = lf.length();
              this.channelsOpened[id] = this.fileHandles[id].writer(start=fileSize);
            }
          }
          wc = this.channelsOpened[id];
          if stdoutOnly {
            wc = stdout;
          }
        } else {
          lf = open('logs/V-' + hstring.currentTask + '.log' : string, iomode.cw);
          this.filesOpened.add(id);
          this.channelsOpened[id] = lf.writer();
          this.fileHandles[id] = lf;
          wc = this.channelsOpened[id];
          if stdoutOnly {
            wc = stdout;
          }
          // First Valkyrie!
          wc.writeln('VALKYRIE TASK: ' + hstring.currentTask : string + ' ID: ' + id : string);
          wc.writeln('');
        }
        useStdout = false;
      } else {
        id = 'stdout';
      }
      if this.channelDebugPath[id] == vstring.path() {
        vstring.printedHeader = true;
      } else {
        vstring.printedHeader = false;
        this.channelDebugPath[id] = vstring.path();
      }
      vstring.time = '%010.2dr'.format(Time.getCurrentTime() - this.time);
      //vstring =  + vstring.sep + vstring;
      var tm: int;
      if debugLevel != this.channelDebugHeader[id] {
        wc.writeln(this.formatHeader(debugLevel));
        if useStdout {
          this.channelsOpened[id].writeln(this.formatHeader(debugLevel));
        }
        this.channelDebugHeader[id] = debugLevel;
      }
      //wc.write(' '*(this.indent*3));
      if header {
        wc.write(vstring);
        for m in msg {
          tm += m.size+1;
          wc.write(m : string, ' ');
          if useStdout {
            this.channelsOpened[id].write(m : string, ' ');
          }
        }
        wc.writeln('');
        if useStdout {
          this.channelsOpened[id].writeln('');
        }
      } else {
        wc.write(' '*(this.indent+1), vstring);
        if useStdout {
          this.channelsOpened[id].write(' '*(this.indent+1), vstring);
        }
        tm = (' '*(this.indent*3)).size;
        for im in msg {
          for m in im.split(' ',maxsplit = -1) {
            if tm + m.size > this.maxCharacters {
              wc.writeln('');
              wc.write(' '*((this.indent*3)+13));
              if useStdout {
                this.channelsOpened[id].writeln('');
                this.channelsOpened[id].write(' '*this.indent*3);

              }
              tm = this.indent*3;
            }
            tm += m.size+1;
            wc.write(m : string, ' ');
            if useStdout {
              this.channelsOpened[id].write(m : string, ' ');
            }
          }
        }
        wc.writeln('');
        if useStdout {
          this.channelsOpened[id].writeln('');
        }
      }
      if id != 'stdout' {
        //writeln(wc.type : string);
        if flushToLog {
          wc.close();
          this.fileHandles[id].fsync();
        }
      }
      l.unlock();
    }

    proc genericMessage(msg, mtype: int, debugLevel: string, gt: bool) {
      if gt {
        if this.currentDebugLevel <= mtype {
          this.printToConsole(msg, debugLevel, hstring=new yggHeader());
        }
      } else {
        if this.currentDebugLevel == mtype {
          this.printToConsole(msg, debugLevel, hstring=new yggHeader());
        }
      }
    }

    proc genericMessage(msg, mtype: int, debugLevel: string, hstring: yggHeader, gt: bool) {
      if gt {
        if this.currentDebugLevel <= mtype {
          this.printToConsole(msg, debugLevel, hstring, header=false);
        }
      } else {
        if this.currentDebugLevel == mtype {
          this.printToConsole(msg, debugLevel, hstring, header=false);
        }
      }
    }

    proc genericMessage(msg, mtype: int, debugLevel: string, hstring: yggHeader, gt: bool, header: bool) {
      if gt {
        if this.currentDebugLevel <= mtype {
          this.printToConsole(msg, debugLevel, hstring, header);
        }
      } else {
        if this.currentDebugLevel == mtype {
          this.printToConsole(msg, debugLevel, hstring, header);
        }
      }
    }

    proc debug(msg...?n) {
      this.genericMessage(msg, this.DEBUG, 'DEBUG', gt=true);
    }

    proc debug(msg...?n, hstring: yggHeader) {
      this.genericMessage(msg, this.DEBUG, 'DEBUG', hstring, gt=true);
    }

    proc devel(msg...?n) {
      this.genericMessage(msg, this.DEVEL, 'DEVEL', gt=false);
    }

    proc devel(msg...?n, hstring: yggHeader) {
      this.genericMessage(msg, this.DEVEL, 'DEVEL', hstring, gt=false);
    }

    proc warning(msg...?n) {
      this.genericMessage(msg, this.WARNING, 'WARNING', gt=true);
    }

    proc warning(msg...?n, hstring: yggHeader) {
      this.genericMessage(msg, this.WARNING, 'WARNING', hstring, gt=true);
    }

    proc log(msg...?n) {
      this.genericMessage(msg, this.RUNTIME, 'RUNTIME', gt=true);
    }

    proc log(msg...?n, hstring: yggHeader) {
      this.genericMessage(msg, this.RUNTIME, 'RUNTIME', hstring, gt=true);
    }

    proc critical(msg...?n, hstring: yggHeader) {
      this.genericMessage(msg, this.currentDebugLevel, 'CRITICAL FAILURE', hstring, gt=true);
    }

    proc critical(msg...?n) {
      this.genericMessage(msg, this.currentDebugLevel, 'CRITICAL FAILURE', hstring=new yggHeader(), gt=true);
    }

    proc header(msg...?n) {
      var yh = new yggHeader();
      yh.printedHeader = true;
      yh.useTime = false;
      this.genericMessage((msg), this.RUNTIME, 'RUNTIME', hstring=yh, gt=true, header=true);
    }

    proc header(msg...?n, in hstring: yggHeader) {
      //var yh = new yggHeader();
      hstring.printedHeader = true;
      hstring.useTime = false;
      this.genericMessage((msg), this.RUNTIME, 'RUNTIME', hstring=hstring, gt=true, header=true);
    }

  }

}
