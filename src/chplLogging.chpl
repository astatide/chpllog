/*

    A logging module.  Supports multiple run/log levels (such as DEBUG, RUNTIME,
    etc) and multiple output channels (useful for logging output from individual
    tasks).  Messages can be written to a channel any level simply by calling
    the level appropriate function.  Write requests are ignored if the current
    runtime is greater than the runtime level of the call.

    As an example:

    .. highlight:: chapel

    ::

      use chplLogging;

      var log = new owned chplLogging.chplLogger();
      log.currentDebugLevel = 0;
      var chmain = new chplLogging.logHeader();
      chmain.header = 'stdout';

      log.header('Test of logging infrastructure', chmain);
      log.debug('Starting %i tasks'.format(6), chmain);

      forall v in 1..6 {
        var ch = new chplLogging.logHeader();
        ch.id = v : string; // Cast it to a string
        ch.header = 'V%i'.format(v); // now, any subsequent calls with this ch will be written to V%s.log
        log.header('TESTING TASK ID:', v : string, ch);
        log.log('Hello, world, from log file V%i!'.format(v), ch);
        mainFunction(ch);
        log.critical('END - Normally, only use me for failure events.', ch);
      }

      log.log('Ending!', chmain);

      // We can also use this to set a stack trace.  We can pass around ch and add
      // strings to it to let us know what function is calling.

      proc mainFunction(in ch: chplLogging.logHeader) throws {
        ch += 'mainFunction';
        log.log('Calling!', ch);
        secondaryFunction(ch);
        log.log('Calling!', ch);

      }

      proc secondaryFunction(in ch: chplLogging.logHeader) {
        ch += 'secondaryFunction';
        log.log('Calling!', ch);

      }

    produces the following stdout

    ::

      ///// RUNTIME //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
      Test of logging infrastructure
      ///// DEBUG ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                     0000000.00 - Starting 6 tasks
      ///// RUNTIME //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                     0000000.00 - Ending!

    and 6 log files, similar to the following (V1.log)

    ::

      TASK: 0 ID: 1

      ///// RUNTIME //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
            TESTING TASK ID: 1
                     0000000.00 - Hello, world, from log file V1!

            //mainFunction//
                     0000000.00 - Calling!

            //mainFunction////secondaryFunction//
                     0000000.00 - Calling!

            //mainFunction//
                     0000000.00 - Calling!
      ///// CRITICAL FAILURE /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


                     0000000.00 - END - Normally, only use me for failure events.

 */

module chplLogging {

  /*
      If set to true, we explicitly call an fsync on the file and channel
      every time we log.  Useful for debugging when your program might just
      kick the bucket without properly closing the file.

      Defaults to false.

  */

  config const flushToLog: bool = false;

  /*
      If set to true, calls fsync on file channels every time a log function
      is called.  This is useful for debugging, as it ensures that the log files
      are written to before the program crashes.

      Defaults to false.

  */
  config const stdoutOnly: bool = false;

  use spinlock;
  use IO;
  use Time;

  /*

  A record specifying where and how a message should be written.  This is
  passed through to the function calls such as `log` and `debug`, which the
  printToConsole method in chplLogger uses to determine whether to open a new
  channel, use an existing one, or send in to stdout.  By default, it's set to
  use stdout.

  :arg levels: How many layers deep should the stack trace (or whatever else is
    in msg) go?  Defaults to 10.

  :arg m: The domain for msg.  This is an int domain and is used to ensure that
    order of addition is kept when printing msg back out.

  :arg msg: The set of strings that make up the header.  This is printed to a
    channel when printedHeader = true; the chplLogger simply calls `write` on the
    logHeader, and the writeThis() function prints the header if necessary.
    By default, this is treated as a stack trace: each element in the msg array is
    printed in the order it was added, separated by `sep`, starting at the end
    and going `levels` back.  To add to this array, simply + a string to the logHeader.

  :arg sep: The string to use to separate elements in msg when writing.

  :arg id: an ID that is used internally as a name for the channel.  Note that
    to ensure different messages are sent to different channels, the ids of two
    different logHeaders must be unique.  Otherwise, the channels will overwrite
    each other

  :arg header: used to identify whether or not the message should be sent
    to stdout, or to a file.  header is used as the filename, and is kept
    different from id to allow multiple channels to write to the same file.
    Since chplLogger blocks, writes should be safe.

  :arg currentTask: An optional value which can be used to track which logHeader
    is being used in which task.  Can also be used for naming files.

  :arg time: The initial creation time of the logHeader.  This is used to
    timestamp the time that messages are written (not the time that a write
    was requested).

  :arg printedHeader: If false, writeThis() will print the header.  Otherwise,
    the header is ignored.

  :arg useTime: Whether or not to timestamp a message.

  */

  record logHeader {
    // How many levels of the stack to report?
    var levels: int = 10;
    var m: domain(int);
    var msg: [m] string;
    var sep: string = '//';
    // Given to us by the Valkyries above.
    var id: string = 'stdout';
    var currentTask: int;
    // header should actually be sendTo
    var header: string;
    var time: string;
    var printedHeader: bool = false;
    var useTime: bool = true;

    proc writeThis(wc) {
      // this is function to allow this to be written directly.
      // mason test is whiny.
      try {
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
      } catch {}
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

  /*

  Function overloads for the logHeader which allow add strings, in order, to the
  internal domain to allow for simplification of a stack trace.

  */

  proc +(a: logHeader, b: string) {
    var y = new logHeader();
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

  /*

  Same as above, but in the reverse case.

  */

  proc +(b: string, a: logHeader) {
    var y = new logHeader();
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

  /*

  In case you like a good in-place addition.

  */

  proc +=(ref a: logHeader, b: string) {
    a.m.add(a.m.size+1);
    a.msg[a.m.size+1] = b;
  }

  /*

  The logging module.  This is what is responsible for storing file handles,
  channels, and most of the formatting options.

  :arg currentDebugLevel: What level of messages to print.  Valid values are
    -1, 0, 1, and 2.  -1 should not be used externally and is used to disable
    every log call that is NOT called with .devel().  This is the type of thing
    you would set with a configuration flag, for instance.

  :arg maxCharacters: how many characters can be printed on one line before
    a new line is written.  Note that this is 'fuzzy' currently.  Eventually,
    you'll be able to disable newlines altogether (useful when making a log
    searchable or human readable).

  :arg headerStarter: Filler character used in the various headers.

  :arg indent: How many spaces should proceed each message?

  :arg fileName: What logfile should stdout go to?

  :arg logsDir: What directory logs should be stored in.

  */

  class chplLogger {
    // This is a class to let us handle all input and output.
    var currentDebugLevel: int;

    /* Constants for use in determing log levels */
    var DEVEL = -1;
    var DEBUG = 0;
    var WARNING = 1;
    var RUNTIME = 2;
    var maxCharacters = 160;
    var headerStarter = '/';
    var indent = 5;
    var l = new shared spinlock.SpinLock();
    var tId: int;
    var filesOpened: domain(string);
    var channelsOpened: [filesOpened] channel(true,iokind.dynamic,true);
    var channelDebugHeader: [filesOpened] string;
    var channelDebugPath: [filesOpened] string;
    var fileHandles: [filesOpened] file;
    var lastDebugHeader = '';
    var time = Time.getCurrentTime();
    var fileName = 'chpl.log';
    var logsDir = '';

    /* Called in the event of a shutdown to ensure channels are closed and files are synced */

    proc exitRoutine() {
      for id in this.filesOpened {
        try {
          this.channelsOpened[id].writeln('EXCEPTION CAUGHT');
          this.channelsOpened[id].close();
          this.fileHandles[id].fsync();
        } catch {
          // And then do nothing.
        }
      }
    }

    /* Formats the debugLevel header, not the stack trace header. */

    proc formatHeader(mtype: string) {
      // Formats a header for us to print out to stdout.
      var header = ' '.join(this.headerStarter*5, mtype, this.headerStarter);
      var nToEnd = this.maxCharacters - header.size;
      header = header + (this.headerStarter*nToEnd);
      return header;
    }

    /*

    The bulk of the logic.  This is responsible for parsing the logHeader,
    determining what channel should be written to, and opening it if necessary.
    Note that things can be sent to both stdout AND a log file for stdout (think
    of the tee program).  It determines whether the incoming message is of the
    same debugLevel or not, and if not, prints a new header.

    Do not call this directly; it only prints what it's told to print.

    Has separate logic for 'regular' or 'header' type messages; header type
    messages are things like logos, etc.  They are not timestamped and
    have slightly different formatting.  They are also not assumed to be splittable.

    */


    proc printToConsole(msg, debugLevel: string, lh: logHeader, header: bool) throws {
      // check whether we're going to stdout or not.
      var wc = stdout;
      var useStdout: bool = true;
      var vstring = lh;
      var lf: file;
      var lastDebugHeader: string;
      l.lock();
      var id: string;

      if this.lastDebugHeader == '' {
        if !this.filesOpened.contains('stdout') {
          this.filesOpened.add('stdout');
          var lf = open(this.fileName, iomode.cw);
          this.fileHandles['stdout'] = lf;
          this.channelsOpened['stdout'] = lf.writer();
        }
      }

      if lh.header != 'stdout' {
        id = lh.id;
        // First, check to see whether we've created the file.
        if this.filesOpened.contains(id) {
          if flushToLog {
            // This is in the event that we want to ensure our files are synced.
            // Useful for debugging.
            lf = this.fileHandles[id];
            var fileSize = lf.length();
            this.channelsOpened[id] = this.fileHandles[id].writer(start=fileSize);
          }
          wc = this.channelsOpened[id];
          if stdoutOnly {
            wc = stdout;
          }
        } else {
          // I wonder if there's an os.join like functionality in Chapel?
          if this.logsDir != '' {
            lf = open(this.logsDir + '/' + lh.header + '.log' : string, iomode.cw);
          } else {
            // that header is empty yo.  writeln('TESTING! ', lh.header);
            lf = open(lh.header + '.log' : string, iomode.cw);
          }
          this.filesOpened.add(id);
          this.channelsOpened[id] = lf.writer();
          this.fileHandles[id] = lf;
          wc = this.channelsOpened[id];
          if stdoutOnly {
            wc = stdout;
          }
          wc.writeln('TASK: ' + lh.currentTask : string + ' ID: ' + id : string);
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
      var tm: int;
      if debugLevel != this.channelDebugHeader[id] {
        wc.writeln(this.formatHeader(debugLevel));
        if useStdout {
          this.channelsOpened[id].writeln(this.formatHeader(debugLevel));
        }
        this.channelDebugHeader[id] = debugLevel;
      }
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
        if flushToLog {
          wc.close();
          this.fileHandles[id].fsync();
        }
      }
      l.unlock();
    }

    /*

    Takes input information from the actual log calling functions, determines
    whether the current debugLevel allows it to be written, then calls
    printToConsole if true.

    This version supports not using a logHeader.  You probably shouldn't use it.

    */

    proc genericMessage(msg, mtype: int, debugLevel: string, gt: bool)  {
      try {
        if gt {
          if this.currentDebugLevel <= mtype {
            this.printToConsole(msg, debugLevel, lh=new logHeader(), header=false);
          }
        } else {
          if this.currentDebugLevel == mtype {
            this.printToConsole(msg, debugLevel, lh=new logHeader(), header=false);
          }
        }
      } catch {
        // hmmm.
      }
    }

    /*

    Same as above, but supports using an actual logHeader.

    */

    proc genericMessage(msg, mtype: int, debugLevel: string, lh: logHeader, gt: bool)  {
      try {
        if gt {
          if this.currentDebugLevel <= mtype {
            this.printToConsole(msg, debugLevel, lh, header=false);
          }
        } else {
          if this.currentDebugLevel == mtype {
            this.printToConsole(msg, debugLevel, lh, header=false);
          }
        }
      } catch {
        // what, you gonna cry about it?
      }
    }

    /*

    Not too different from the above, but is used solely by the .header() method.

    */

    proc genericMessage(msg, mtype: int, debugLevel: string, lh: logHeader, gt: bool, header: bool)  {
      try {
        if gt {
          if this.currentDebugLevel <= mtype {
            this.printToConsole(msg, debugLevel, lh, header);
          }
        } else {
          if this.currentDebugLevel == mtype {
            this.printToConsole(msg, debugLevel, lh, header);
          }
        }
      } catch {
        // you think anyone cares about those errors?  Hmmm?  Do you?
        // Do you want your whole program to fail because you imported a shoddy
        // module?  Not that I'm saying it's shoddy.  It's not.  It's just still
        // in development.
      }
    }

    /* Call this in your program to do debug logging */

    proc debug(msg...?n) {
      this.genericMessage(msg, this.DEBUG, 'DEBUG', gt=true);
    }

    /* Call this in your program to do debug logging w/ a logHeader */

    proc debug(msg...?n, in lh: logHeader) {
      this.genericMessage(msg, this.DEBUG, 'DEBUG', lh, gt=true);
    }

    /* Call this in your program to do DEVEL type logging, sans logHeader */

    proc devel(msg...?n) {
      this.genericMessage(msg, this.DEVEL, 'DEVEL', gt=false);
    }

    /* Call this in your program to do DEVEL type logging */

    proc devel(msg...?n, in lh: logHeader) {
      this.genericMessage(msg, this.DEVEL, 'DEVEL', lh, gt=false);
    }

    /* Call this in your program to call a RUNTIME WARNING, sans logHeader */

    proc warning(msg...?n) {
      this.genericMessage(msg, this.WARNING, 'WARNING', gt=true);
    }

    /* Call this in your program to call a RUNTIME WARNING */

    proc warning(msg...?n, in lh: logHeader) {
      this.genericMessage(msg, this.WARNING, 'WARNING', lh, gt=true);
    }

    /* Call this in your program for normal program logging, sans logHeader */

    proc log(msg...?n) {
      this.genericMessage(msg, this.RUNTIME, 'RUNTIME', gt=true);
    }

    /* Call this in your program for normal program logging */

    proc log(msg...?n, in lh: logHeader) {
      this.genericMessage(msg, this.RUNTIME, 'RUNTIME', lh, gt=true);
    }

    /* Call this in your program for critical failure messages. */

    proc critical(msg...?n, in lh: logHeader) {
      this.genericMessage(msg, this.currentDebugLevel, 'CRITICAL FAILURE', lh, gt=true);
    }

    /* Call this in your program for critical failure messages, sans logHeader. */

    proc critical(msg...?n) {
      this.genericMessage(msg, this.currentDebugLevel, 'CRITICAL FAILURE', lh=new logHeader(), gt=true);
    }

    /* Call this in your program to print out logo-type messages, sans logHeader. */

    proc header(msg...?n) {
      var yh = new logHeader();
      yh.printedHeader = true;
      yh.useTime = false;
      this.genericMessage((msg), this.RUNTIME, 'RUNTIME', lh=yh, gt=true, header=true);
    }

    /* Call this in your program to print out logo-type messages. */

    proc header(msg...?n, in lh: logHeader) {
      //var yh = new logHeader();
      lh.printedHeader = true;
      lh.useTime = false;
      this.genericMessage((msg), this.RUNTIME, 'RUNTIME', lh=lh, gt=true, header=true);
    }

  }

}
