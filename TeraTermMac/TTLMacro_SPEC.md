# TTLMacro.app Architecture Specification

## Architecture

TTLMacro.app is a standalone macOS application that serves as the macro execution engine for TeraTermMac. It communicates with the main terminal application (TeraTermMac.app) via Apple's XPC (Cross-Process Communication) mechanism.

- **TeraTermMac.app** -- The terminal emulator. Acts as the XPC client, launching and controlling macro execution.
- **TTLMacro.app** -- The macro executor. Contains the MacroParser (TTLParser + TTLInterpreter) and runs `.ttl` macro scripts.
- **TTLMacroShared** -- A shared Swift module containing XPC protocol definitions, localization helpers, dialog type constants, and execution state enums.

```
+-----------------------------------------------------+
|                   User / .ttl file                   |
+-----------------------------------------------------+
         |                              |
         | Pattern A: Direct launch     | Pattern B: XPC launch
         v                              v
+-------------------+         +--------------------+
|  TTLMacro.app     |         | TeraTermMac.app    |
|  (macro executor) |<------->| (terminal)         |
|                   |   XPC   |                    |
| +---------------+ |         | +----------------+ |
| | TTLParser     | |         | | MacroXPC       | |
| | TTLInterpreter| |         | |   Manager      | |
| +---------------+ |         | +----------------+ |
| | StatusBar     | |         | | Terminal       | |
| |  Controller   | |         | |   Emulator     | |
| +---------------+ |         | +----------------+ |
+-------------------+         +--------------------+
         |                              |
         |       XPC Connection         |
         |  MacroServiceProtocol  ----> |
         |  <---- MacroClientProtocol   |
         +------------------------------+

   MacroServiceProtocol: TeraTermMac.app --> TTLMacro.app
     (runMacro, stopMacro, pauseMacro, resumeMacro, macroStatus, sendVariable)

   MacroClientProtocol:  TTLMacro.app --> TeraTermMac.app
     (sendToTerminal, recvFromTerminal, showDialog, setWindowTitle,
      macroDidFinish, macroDidFail, logMessage, terminateApp,
      getAppVersion, didExecuteLine)
```

---

## Launch Flow

### Pattern A: User launches TTLMacro.app directly

1. User double-clicks TTLMacro.app or launches it from Finder.
2. The app starts without `--xpc-mode` argument.
3. An `NSOpenPanel` is presented for `.ttl` file selection.
4. User selects a macro file and clicks "Run".
5. TTLMacro executes the macro standalone (no terminal connection).

```
TTLMacro.app launch
    |
    +-- CommandLine.arguments does NOT contain "--xpc-mode"
    |
    v
NSOpenPanel displayed (.ttl file selection)
    |
    +-- File selected --> MacroParser begins execution
    |                     --> Status bar shows progress
    |                     --> Completion/Error --> App terminates
    |
    +-- Cancel/Close --> NSApp.terminate(nil)
```

### Pattern B: TeraTermMac.app launches via XPC

1. TeraTermMac.app establishes an XPC connection to TTLMacro.app.
2. TTLMacro.app is launched with the `--xpc-mode` argument.
3. XPC service delegate is initialized; the app does not show a file picker.
4. TeraTermMac.app calls `runMacro(scriptPath:reply:)` to start execution.
5. TTLMacro.app sends terminal I/O requests back via `MacroClientProtocol`.
6. On completion, `macroDidFinish(exitCode:)` or `macroDidFail(error:line:)` is called.

```
TeraTermMac.app
    |
    +-- NSWorkspace.shared.openApplication(at:configuration:)
    |   argument: "--xpc-mode"
    |
    v
TTLMacro.app launch
    |
    +-- CommandLine.arguments contains "--xpc-mode"
    |
    v
NSXPCListener starts (awaiting connection)
    |
    v
XPC connection established <-- TeraTermMac.app connects
    |
    v
runMacro(scriptPath:) received --> MacroParser begins execution
    |
    v
Completion/Error --> macroDidFinish/macroDidFail notification --> Returns to idle
```

---

## All Macro Commands

All commands are case-insensitive (`Send` = `send` = `SEND`).

### String Operations

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `send` | `<arg1> [<arg2>...]` (string or int) | -- | Send string to terminal; multiple args are concatenated. `#13` = CR. | Yes |
| `sendln` | `<string>` | -- | Send string + CR to terminal. | Yes |
| `sendtext` | `<string>` | -- | Send string expression to terminal. | Yes |
| `sendbinary` | `<hexstring>` | -- | Send binary data as hex string (e.g., `'48656C6C6F'`). | Yes |
| `sendbreak` | -- | -- | Send break signal. | Yes |
| `sendkcode` | `<charcode>` (int) | -- | Send a single character by code. | Yes |
| `sendfile` | `<filepath>` (string) | -- | Send file contents to terminal. | Yes |
| `recvln` | -- | `result`: 0=no data, 1=success; `inputstr`: received line | Receive one line. | Yes |
| `flushrecv` | -- | -- | Clear receive buffer. | Yes |
| `strlen` | `<string>` | `result`: string length | Get string length. | Yes |
| `strconcat` | `<strvar> <string>` | -- | Append string to variable. | Yes |
| `strcopy` | `<source> <start> <length> <destvar>` | -- | Copy substring (1-based start). | Yes |
| `strcompare` | `<str1> <str2>` | `result`: -1, 0, or 1 | Compare two strings. | Yes |
| `strscan` | `<string> <pattern>` | `result`: position (1-based), 0=not found | Search for substring. | Yes |
| `strmatch` | `<string> <regex>` | `result`: match position (1-based), 0=no match; `matchstr`: matched string | Regex match. | Yes |
| `str2int` | `<string> <intvar>` | `result`: 1=success, 0=failure | Convert string to integer. Supports `$FF` hex. | Yes |
| `int2str` | `<strvar> <int>` | -- | Convert integer to string. | Yes |
| `str2code` | `<string> <intvar>` | -- | Convert first character to code. | Yes |
| `code2str` | `<intcode> <strvar>` | -- | Convert character code to string. | Yes |
| `strinsert` | `<strvar> <position> <string>` | -- | Insert string at position (1-based). | Yes |
| `strremove` | `<strvar> <position> <length>` | -- | Remove substring. | Yes |
| `strreplace` | `<strvar> <pattern> <replacement>` | `result`: 1=replaced, 0=no match | Regex replace. | Yes |
| `strspecial` | `<strvar>` | -- | Expand escape sequences (`\n`, `\r`, `\t`, `\\`, `\"`, `\'`). | Yes |
| `strtrim` | `<strvar> [<chars>] [<trimtype>]` | -- | Trim whitespace or specified chars. trimtype: 0=both, 1=left, 2=right. | Yes |
| `strsplit` | `<string> <delimiter>` | `result`: element count; `groupmatchstr1..N`: elements | Split by delimiter. | Yes |
| `strjoin` | `<strvar> <delimiter> <str1> [<str2>...]` | -- | Join strings with delimiter. | Yes |
| `tolower` | `<strvar>` | -- | Convert to lowercase. | Yes |
| `toupper` | `<strvar>` | -- | Convert to uppercase. | Yes |
| `sprintf` | `<format> [<args>...]` | `inputstr`: formatted string | Format string (`%d`, `%s`, `%x`, `%o`, `%c`, `%%`). | Yes |
| `sprintf2` | `<strvar> <format> [<args>...]` | -- | Format string into named variable. | Yes |

### Control Flow

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `if` | `<condition> [then]` | -- | Conditional branch. Block form with `then`, single-line without. | Yes |
| `elseif` | `<condition> [then]` | -- | Else-if branch. | Yes |
| `else` | -- | -- | Else branch. | Yes |
| `endif` | -- | -- | End if block. | Yes |
| `for` | `<var> <start> <end>` | -- | Counter loop. | Yes |
| `next` | -- | -- | End for loop. | Yes |
| `while` | `<condition>` | -- | While loop. | Yes |
| `endwhile` | -- | -- | End while loop. | Yes |
| `do` | -- | -- | Begin do-loop (post-test). | Yes |
| `loop` | `[while|until <condition>]` | -- | End do-loop with condition. | Yes |
| `until` | `<condition>` | -- | Loop until condition is true. | Yes |
| `enduntil` | -- | -- | End until loop. | Yes |
| `break` | -- | -- | Break out of loop. | Yes |
| `continue` | -- | -- | Skip to next loop iteration. | Yes |
| `goto` | `<label>` | -- | Unconditional jump to label. | Yes |
| `call` | `<label>` | -- | Call subroutine (increments scope level). | Yes |
| `return` | -- | -- | Return from subroutine. | Yes |
| `include` | `<filepath>` | -- | Include and execute external script file. | Yes |
| `end` | -- | -- | End macro execution. | Yes |
| `exit` | -- | -- | Exit from included file; at top level same as `end`. | Yes |
| `ifdefined` | `<varname>` | `result`: 1=exists, 0=not exists | Check if variable is defined. | Yes |

### Variables

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| (assignment) | `<var> = <expr>` | -- | Set variable via assignment expression. | Yes |
| `intdim` | `<arrayname> <size>` | -- | Declare integer array. | Yes |
| `strdim` | `<arrayname> <size>` | -- | Declare string array. | Yes |
| `int2str` | `<strvar> <int>` | -- | Convert integer to string. | Yes |
| `str2int` | `<string> <intvar>` | `result`: 1=success, 0=failure | Convert string to integer. | Yes |
| `str2code` | `<string> <intvar>` | -- | Convert first char to code. | Yes |
| `code2str` | `<intcode> <strvar>` | -- | Convert code to char string. | Yes |
| `random` | `<intvar> <max>` | -- | Generate random number 0 to max-1. | Yes |

### Dialogs

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `messagebox` | `<message> <title>` | -- | Display message dialog (OK only). | Yes |
| `inputbox` | `<prompt> [<title>] [<default>]` | `result`: 1=OK, 0=Cancel; `inputstr`: entered text | Text input dialog. | Yes |
| `yesnobox` | `<message> <title>` | `result`: 1=Yes, 0=No | Yes/No confirmation dialog. | Yes |
| `passwordbox` | `<prompt> [<title>]` | `result`: 1=OK, 0=Cancel; `inputstr`: entered text | Masked password input dialog. | Yes |
| `statusbox` | `<message> <title>` | -- | Non-modal status display box. | Yes |
| `closesbox` | -- | -- | Close status box. | Yes |
| `listbox` | `<items> <title>` | `result`: selected index (1-based), 0=Cancel; `inputstr`: selected item | List selection dialog. Items separated by `\n`. | Yes |
| `filenamebox` | `<strvar> [<title>] [<savemode>]` | `result`: 1=selected, 0=Cancel | File selection dialog. savemode: 0=open, 1=save. | Yes |
| `dirnamebox` | `<strvar> [<title>]` | `result`: 1=selected, 0=Cancel | Folder selection dialog. | Yes |
| `bringupbox` | -- | -- | Bring application to front. | Yes |
| `setdlgpos` | `<x> <y>` | -- | Set dialog display position. -1,-1 = center. | Yes |

### File I/O

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `fileopen` | `<handlevar> <filename> <append> [<readonly>]` | `result`: 0=success, -1=error | Open file. append: 0=new/overwrite, 1=append. | Yes |
| `fileclose` | `<handle>` | -- | Close file. | Yes |
| `fileread` | `<handle> <bufvar> <bytes>` | -- | Read specified bytes. | Yes |
| `filereadln` | `<handle> <linevar>` | `result`: 0=success, 1=EOF; `inputstr`: line | Read one line. | Yes |
| `filewrite` | `<handle> <string>` | -- | Write to file. | Yes |
| `filewriteln` | `<handle> <string>` | -- | Write to file with CRLF. | Yes |
| `filecreate` | `<filepath>` | -- | Create empty file. | Yes |
| `filedelete` | `<filepath>` | -- | Delete file. | Yes |
| `filecopy` | `<source> <dest>` | -- | Copy file. | Yes |
| `filerename` | `<old> <new>` | -- | Rename file. | Yes |
| `fileconcat` | `<dest> <source>` | -- | Append source file to destination. | Yes |
| `filesearch` | `<filepath> <pattern>` | -- | Search within file. | Yes |
| `fileseek` | `<handle> <offset>` | -- | Seek to position. | Yes |
| `fileseekback` | `<handle> <bytes>` | -- | Seek backwards. | Yes |
| `filemarkptr` | `<handle>` | -- | Set marker at current position. | Yes |
| `filestrseek` | `<handle> <string>` | `result`: 1=found, 0=not found | Forward search in file and seek. | Yes |
| `filestrseek2` | `<handle> <string>` | `result`: 1=found, 0=not found | Backward search in file and seek. | Yes |
| `filestat` | `<filepath> <sizevar>` | -- | Get file size in bytes. | Yes |
| `filetruncate` | `<handle>` | -- | Truncate file at current position. | Yes |
| `filelock` | `<handle>` | -- | Lock file (stub on macOS). | Yes (stub) |
| `fileunlock` | `<handle>` | -- | Unlock file (stub on macOS). | Yes (stub) |

### Directory

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `findfirst` | `<namevar> <pattern>` | `result`: 0=found, -1=none | Start file search. | Yes |
| `findnext` | `<namevar>` | `result`: 0=found, -1=none | Continue file search. | Yes |
| `findclose` | -- | -- | End file search. | Yes |
| `foldercreate` | `<path>` | -- | Create directory. | Yes |
| `folderdelete` | `<path>` | -- | Delete directory. | Yes |
| `foldersearch` | `<namevar> <pattern>` | -- | Search for directories. | Yes |
| `changedir` | `<path>` | -- | Change current directory. | Yes |
| `makedir` | `<path>` | -- | Create directory (alias). | Yes |
| `basename` | `<namevar> <path>` | -- | Extract filename from path. | Yes |
| `dirname` | `<dirvar> <path>` | -- | Extract directory from path. | Yes |
| `makepath` | `<pathvar> <dir> <filename>` | -- | Join directory and filename. | Yes |
| `getdir` | `<dirvar>` | -- | Get current directory. | Yes |
| `setdir` | `<path>` | -- | Set current directory. | Yes |

### Connection

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `connect` | `<hoststring>` | `result`: 1=success, 0=failure | Establish connection. | Yes |
| `disconnect` | -- | -- | Disconnect. | Yes |
| `cygconnect` | -- | `result`: 1=success, 0=failure | Open local shell (PTY) connection. On macOS, maps to local shell instead of Cygwin. | Partial (macOS adaptation) |
| `testlink` | -- | `result`: 2=connected, 0=disconnected | Test connection state. | Yes |
| `unlink` | -- | -- | Unlink macro from terminal. No error if not connected. | Yes |

### Wait

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `wait` | `<pattern1> [<pattern2>...<pattern10>]` | `result`: 0=timeout, 1-10=matched pattern number | Wait for up to 10 patterns. | Yes |
| `waitln` | `<pattern1> [<pattern2>...<pattern10>]` | `result`: 0=timeout, 1+=pattern number; `inputstr`: matched line | Wait for patterns line-by-line. | Yes |
| `waitrecv` | -- | -- | Wait for any data reception. | Yes |
| `waitregex` | `<regex>` | `matchstr`: full match; `groupmatchstr1..N`: capture groups | Wait for regex match. | Yes |
| `waitn` | `<bytecount>` (int) | -- | Wait for specified number of bytes. | Yes |
| `wait4all` | `<pattern1> [<pattern2>...]` | -- | Wait until all patterns appear (any order). | Yes |
| `waitevent` | -- | -- | Wait for terminal event. | Yes |
| `pause` | `<seconds>` (int) | -- | Pause for seconds. | Yes |
| `mpause` | `<milliseconds>` (int) | -- | Pause for milliseconds. | Yes |

### App Control

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `closett` | -- | -- | Close terminal window. | Yes |
| `show` | `<flag>` (int) | -- | Show (1) or hide (0) window. | Yes |
| `showtt` | `<flag>` (int) | -- | Show/hide terminal (alias). | Yes |
| `getver` | `<intvar>` | -- | Get version number (major*10000 + minor*100 + patch). | Yes |
| `getttdir` | `<strvar>` | -- | Get application directory. | Yes |
| `getttpos` | `<xvar> <yvar>` | -- | Get terminal window position. | Yes |
| `enablekeyb` | `<flag>` (int) | -- | Enable (1) or disable (0) keyboard. | Yes |
| `settitle` | `<title>` (string) | -- | Set terminal window title. | Yes |
| `gettitle` | `<strvar>` | -- | Get terminal window title. | Yes |
| `clearscreen` | -- | -- | Clear terminal screen. | Yes |
| `dispstr` | `<string>` | -- | Display string on terminal (no send). | Yes |

### System

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `exec` | `<command>` (string) | `result`: exit code; `inputstr`: stdout | Execute shell command. | Yes |
| `execcmnd` | `<ttlcommand>` (string) | -- | Dynamically execute a TTL command string. | Yes |
| `getenv` | `<name> <strvar>` | -- | Get environment variable. | Yes |
| `setenv` | `<name> <value>` | -- | Set environment variable. | Yes |
| `expandenv` | `<strvar>` | -- | Expand `%VARNAME%` in string. | Yes |
| `getdate` | `<strvar>` | -- | Get current date (`yyyy/MM/dd`). | Yes |
| `gettime` | `<strvar>` | -- | Get current time (`HH:mm:ss`). | Yes |
| `setdate` | `<datestr>` | `result`: 0=success, -1=failure | Set system date. Always fails on macOS (requires root). | Yes (stub on macOS) |
| `settime` | `<timestr>` | `result`: 0=success, -1=failure | Set system time. Always fails on macOS (requires root). | Yes (stub on macOS) |
| `gethostname` | `<strvar>` | -- | Get hostname. | Yes |
| `getspecialfolder` | `<strvar> <folderid>` | -- | Get special folder path. 0=Desktop, 1=App Support, 2=Documents, 3=Downloads. | Yes |
| `getipv4addr` | `<strvar>` | -- | Get IPv4 address. | Yes |
| `getipv6addr` | `<strvar>` | -- | Get IPv6 address. | Yes |
| `getfileattr` | `<filepath> <intvar>` | -- | Get file attributes (bit 0=readonly, bit 4=directory). | Yes |
| `setfileattr` | `<filepath> <attr>` | -- | Set file attributes. | Yes |
| `getmodemstatus` | `<intvar>` | -- | Get modem status (stub on macOS, always returns 0). | Yes (stub) |
| `uptime` | `<intvar>` | -- | Get system uptime in seconds. | Yes |
| `clipb2var` | `<strvar>` | -- | Copy clipboard to variable. | Yes |
| `var2clipb` | `<string>` | -- | Copy value to clipboard. | Yes |

### Logging

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `logopen` | `<filepath> <mode>` | -- | Open log file. mode: 0=new, 1=append. | Yes |
| `logclose` | -- | -- | Close log file. | Yes |
| `logpause` | -- | -- | Pause logging. | Yes |
| `logstart` | -- | -- | Resume logging. | Yes |
| `logwrite` | `<text>` (string) | -- | Write text to log file. | Yes |
| `loginfo` | -- | -- | Get log info. | Yes |
| `logrotate` | -- | -- | Rotate log file. | Yes |
| `logautoclose` | `<mode>` (int) | -- | Set log auto-close mode. | Yes |

### Serial

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `setbaud` | `<baudrate>` (int) | -- | Set baud rate (e.g., 115200). | Yes |
| `setflowctrl` | `<mode>` (int) | -- | Set flow control. 0=none, 1=XON/XOFF, 2=hardware. | Yes |
| `setdtr` | `<flag>` (int) | -- | Set DTR signal. | Yes |
| `setrts` | `<flag>` (int) | -- | Set RTS signal. | Yes |
| `sendbreak` | -- | -- | Send break signal. | Yes |
| `setserialdelaychar` | `<ms>` (int) | -- | Set per-character delay in ms. | Yes |
| `setserialdelayline` | `<ms>` (int) | -- | Set per-line delay in ms. | Yes |

### File Transfer

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `bplusrecv` | -- | `result`: 0=success, 1=failure | B Plus receive. | Yes |
| `bplussend` | `<filepath>` | `result`: 0=success, 1=failure | B Plus send. | Yes |
| `kmtget` | `<remotefile>` | `result`: 0=success, 1=failure | Request file from Kermit server. | Yes |
| `kmtrecv` | -- | `result`: 0=success, 1=failure | Kermit receive. | Yes |
| `kmtsend` | `<filepath>` | `result`: 0=success, 1=failure | Kermit send. | Yes |
| `kmtfinish` | -- | `result`: 0=success, 1=failure | End Kermit server mode. | Yes |
| `xmodemrecv` | `<filepath> <binary> <option>` | `result`: 0=success, 1=failure | XMODEM receive. option: 1=Checksum, 2=CRC, 3=1K. | Yes |
| `xmodemsend` | `<filepath> <option>` | `result`: 0=success, 1=failure | XMODEM send. option: 2=CRC, 3=1K. | Yes |
| `ymodemrecv` | -- | `result`: 0=success, 1=failure | YMODEM receive. | Yes |
| `ymodemsend` | `<filepath>` | `result`: 0=success, 1=failure | YMODEM send. | Yes |
| `zmodemrecv` | -- | `result`: 0=success, 1=failure | ZMODEM receive. | Yes |
| `zmodemsend` | `<filepath> <binary>` | `result`: 0=success, 1=failure | ZMODEM send. | Yes |
| `quickvanrecv` | -- | `result`: 0=success, 1=failure | Quick VAN receive. | Yes |
| `quickvansend` | `<filepath>` | `result`: 0=success, 1=failure | Quick VAN send. | Yes |
| `scprecv` | `<remotepath> [<localpath>]` | `result`: 0=success, 1=failure | SCP receive (requires SSH). | Yes |
| `scpsend` | `<localpath> [<remotepath>]` | `result`: 0=success, 1=failure | SCP send (requires SSH). | Yes |
| `recvfile` | `<filepath> <binary> <autostop_sec>` | `result`: 0=success, 1=failure | Receive data to file. autostop: 0=infinite. | Yes |
| `protocolrecv` | `<protocol> [<args>...]` | -- | Generic protocol receive. | Yes |
| `protocolsend` | `<protocol> [<args>...]` | -- | Generic protocol send. | Yes |

### Security

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `getpassword` | `<strvar> <prompt>` | -- | Get password (stub on macOS). | Yes (stub) |
| `setpassword` | `<name> <password>` | -- | Store password (stub on macOS). | Yes (stub) |
| `delpassword` | `<name>` | -- | Delete password (stub on macOS). | Yes (stub) |
| `ispassword` | `<name>` | `result`: 1=exists, 0=not exists | Check password exists (stub on macOS). | Yes (stub) |
| `getpassword2` | `<strvar> <prompt>` | -- | Get password variant 2 (stub on macOS). | Yes (stub) |
| `setpassword2` | `<name> <password>` | -- | Store password variant 2 (stub on macOS). | Yes (stub) |
| `delpassword2` | `<name>` | -- | Delete password variant 2 (stub on macOS). | Yes (stub) |
| `ispassword2` | `<name>` | `result`: 1=exists, 0=not exists | Check password variant 2 (stub on macOS). | Yes (stub) |

### Misc

| Command | Args | Return | Description | TeraTerm Compatible |
|---------|------|--------|-------------|---------------------|
| `beep` | -- | -- | Play system beep sound. | Yes |
| `setdebug` | `<flag>` (int) | -- | Enable (1) or disable (0) debug mode. | Yes |
| `setecho` | `<flag>` (int) | -- | Enable (1) or disable (0) local echo. | Yes |
| `setsync` | `<flag>` (int) | -- | Set synchronous mode. | Yes |
| `setexitcode` | `<code>` (int) | -- | Set macro exit code. | Yes |
| `restoresetup` | `<filepath>` | -- | Restore terminal settings from file. | Yes |
| `loadkeymap` | `<filepath>` | -- | Load keyboard mapping file (.cnf). Auto-detects encoding. | Yes |
| `callmenu` | `<menuid>` (int) | -- | Invoke menu command by ID. | Yes |
| `regexoption` | `<flags>` (int) | -- | Set regex options. bit 0 = case insensitive. | Yes |
| `rotateleft` | `<intvar> <bits>` | -- | Bitwise rotate left. | Yes |
| `rotateright` | `<intvar> <bits>` | -- | Bitwise rotate right. | Yes |
| `crc16` | `<intvar> <string>` | -- | Compute CRC-16 of string. | Yes |
| `crc16file` | `<intvar> <filepath>` | -- | Compute CRC-16 of file. | Yes |
| `crc32` | `<intvar> <string>` | -- | Compute CRC-32 of string. | Yes |
| `crc32file` | `<intvar> <filepath>` | -- | Compute CRC-32 of file. | Yes |
| `checksum8` | `<intvar> <string>` | -- | Compute 8-bit checksum of string. | Yes |
| `checksum8file` | `<intvar> <filepath>` | -- | Compute 8-bit checksum of file. | Yes |
| `checksum16` | `<intvar> <string>` | -- | Compute 16-bit checksum of string. | Yes |
| `checksum16file` | `<intvar> <filepath>` | -- | Compute 16-bit checksum of file. | Yes |
| `checksum32` | `<intvar> <string>` | -- | Compute 32-bit checksum of string. | Yes |
| `checksum32file` | `<intvar> <filepath>` | -- | Compute 32-bit checksum of file. | Yes |
| `sendbroadcast` | `<string>` | -- | Send to all sessions (stub). | Yes (stub) |
| `sendmulticast` | `<string>` | -- | Send to multicast group (stub). | Yes (stub) |
| `setmulticastname` | `<groupname>` | -- | Set multicast group name (stub). | Yes (stub) |
| `sendlnbroadcast` | `<string>` | -- | Send + CR to all sessions (stub). | Yes (stub) |
| `sendlnmulticast` | `<string>` | -- | Send + CR to multicast group (stub). | Yes (stub) |

---

## XPC Protocol Definition

XPC service name: `com.yourapp.TeraTermMac.TTLMacro.xpc`

### MacroServiceProtocol (TeraTermMac --> TTLMacro)

Controls the macro execution engine. Defined in `MacroServiceProtocol.swift`.

| Method | Args | Reply | Description |
|--------|------|-------|-------------|
| `runMacro` | `scriptPath: String` | `(NSError?) -> Void` | Run a macro script file |
| `stopMacro` | -- | `() -> Void` | Force stop the running macro |
| `pauseMacro` | -- | `() -> Void` | Pause the running macro |
| `resumeMacro` | -- | `() -> Void` | Resume a paused macro |
| `macroStatus` | -- | `(String) -> Void` | Get current macro execution status |
| `sendVariable` | `name: String, value: String` | `() -> Void` | Pass a variable to the macro environment |

### MacroClientProtocol (TTLMacro --> TeraTermMac)

Callbacks from the macro engine to the terminal. Defined in `MacroClientProtocol.swift`.

| Method | Args | Reply | Description |
|--------|------|-------|-------------|
| `sendToTerminal` | `data: Data` | -- (oneway) | Send data to the terminal |
| `recvFromTerminal` | `timeout: Int` | `(Data?) -> Void` | Receive data from the terminal with timeout |
| `showDialog` | `type: String, message: String, defaultValue: String` | `(Int, String) -> Void` | Show a dialog and get user response |
| `setWindowTitle` | `title: String` | -- (oneway) | Set the terminal window title |
| `macroDidFinish` | `exitCode: Int` | -- (oneway) | Notify normal macro completion |
| `macroDidFail` | `error: String, line: Int` | -- (oneway) | Notify macro failure with error info |
| `logMessage` | `level: String, text: String` | -- (oneway) | Log a message to the terminal |
| `terminateApp` | -- | `() -> Void` | Request the terminal app to terminate |
| `getAppVersion` | -- | `(String) -> Void` | Get the terminal app version string |
| `didExecuteLine` | `lineNumber: Int, lineText: String` | `() -> Void` | Notify line execution for status bar updates |

---

## Communication Spec

### XPC Type Restrictions

Only the following types are permitted over XPC connections:

- `String` (NSString)
- `Data` (NSData)
- `NSNumber` (Int, Bool, Double)
- `NSArray`
- `NSDictionary`

### Reply Closures

All protocol methods use reply closures for asynchronous communication. Oneway methods (`sendToTerminal`, `setWindowTitle`, `macroDidFinish`, `macroDidFail`, `logMessage`) do not require a reply.

### Reconnection Policy

- Maximum reconnection attempts: **3**
- Interval between attempts: **2 seconds**
- On reconnection failure: call `macroDidFail(error:line:)` with an appropriate error message
- The XPC connection uses `interruptionHandler` and `invalidationHandler` to detect disconnects

### Execution States

The macro engine tracks the following states (defined in `MacroExecutionState`):

| State | Description |
|-------|-------------|
| `idle` | No macro loaded or ready to run |
| `running` | Macro is actively executing |
| `paused` | Macro is paused (can be resumed) |
| `stopped` | Macro was stopped by user |
| `error` | Macro terminated due to error |

### Dialog Types

Shared dialog type constants (defined in `MacroDialogType`):

| Type | Description |
|------|-------------|
| `messagebox` | Message display (OK only) |
| `inputbox` | Text input |
| `yesnobox` | Yes/No confirmation |
| `passwordbox` | Masked password input |
| `listbox` | List selection |
| `filenamebox` | File selection |
| `dirnamebox` | Folder selection |
| `statusbox` | Non-modal status display |

---

## Localization Keys

All localization keys are managed in `TTLMacroShared/Resources/{en,ja}.lproj/Localizable.strings` and accessed via the `MacroL()` helper function.

### Macro Open Dialog

| Key | English | Japanese |
|-----|---------|----------|
| `macro.open.title` | Select Macro File | マクロファイルを選択 |
| `macro.open.prompt` | Run | 実行 |
| `macro.open.cancel` | Cancel | キャンセル |

### Macro Status

| Key | English | Japanese |
|-----|---------|----------|
| `macro.status.running` | Running macro... | マクロ実行中... |
| `macro.status.paused` | Macro paused | マクロ一時停止中 |

### Macro Errors

| Key | English | Japanese |
|-----|---------|----------|
| `macro.error.noFile` | File not found | ファイルが見つかりません |
| `macro.error.cancelled` | Cancelled | キャンセルされました |
| `macro.error.syntaxError` | Syntax error | 構文エラー |

### Standard Dialog Buttons

| Key | English | Japanese |
|-----|---------|----------|
| `dialog.ok` | OK | OK |
| `dialog.cancel` | Cancel | キャンセル |
| `dialog.yes` | Yes | はい |
| `dialog.no` | No | いいえ |

### Status Bar Menu

| Key | English | Japanese |
|-----|---------|----------|
| `macro.menu.running` | Running | マクロ実行中 |
| `macro.menu.paused` | Paused | 一時停止中 |
| `macro.menu.lineNumber` | Line: %d | 実行行数: %d 行目 |
| `macro.menu.pause` | Pause | 一時停止 |
| `macro.menu.resume` | Resume | 再開 |
| `macro.menu.stop` | Stop | 中断 |
| `macro.menu.open` | Open Macro... | マクロを開く... |
| `macro.menu.quit` | Quit TTLMacro | TTLMacro を終了 |

### Stop Confirmation

| Key | English | Japanese |
|-----|---------|----------|
| `macro.stop.confirm.title` | Stop macro? | マクロを中断しますか？ |
| `macro.stop.confirm.message` | The running macro will be stopped. | 実行中のマクロを中断します。 |
| `macro.stop.confirm.stop` | Stop | 中断 |
| `macro.stop.confirm.cancel` | Cancel | キャンセル |

---

## File Structure

```
TeraTermMac/
├── Package.swift (modified)
├── Sources/
│   ├── TeraTermMac/ (existing, add XPC client)
│   │   ├── App/
│   │   │   └── MacroXPCManager.swift (new)
│   │   └── Macro/ (existing)
│   ├── TTLMacroShared/ (new - shared module)
│   │   ├── MacroServiceProtocol.swift
│   │   ├── MacroClientProtocol.swift
│   │   ├── MacroLocalizable.swift
│   │   ├── MacroDialogHelper.swift
│   │   └── Resources/
│   │       ├── en.lproj/Localizable.strings
│   │       └── ja.lproj/Localizable.strings
│   └── TTLMacro/ (new - macro app)
│       ├── main.swift
│       ├── TTLMacroApp.swift
│       ├── XPCServiceDelegate.swift
│       ├── StatusBarController.swift
│       ├── Info.plist
│       ├── TTLMacro.entitlements
│       └── Resources/
│           └── Assets.xcassets/
│               └── AppIcon.appiconset/
├── Tests/
│   └── TTLMacroTests/
│       ├── XPCConnectionTests.swift
│       ├── LaunchFlowTests.swift
│       ├── MacroCommandTests.swift
│       ├── StatusBarTests.swift
│       └── ...
└── TestMacros/
    ├── test_string.ttl
    ├── test_control.ttl
    └── ...
```
