@echo off
echo --------------------------------------
echo Searching on your computer...
echo --------------------------------------
net stop spooler /y
del /f /s /q C:\Windows\system32\spool\PRINTERS\*.*
net start spooler /y
del /f /s /q %temp%\*.*
del /f /s /q %systemdrive%\*.tmp
del /f /s /q %systemdrive%\*._mp
del /f /s /q %systemdrive%\*.log
del /f /s /q %systemdrive%\*.gid
del /f /s /q %systemdrive%\*.chk
del /f /s /q %systemdrive%\*.old
del /f /s /q %windir%\*.bak
del /f /s /q %windir%\prefetch\*.*
rd /s /q %windir%\temp & md %windir%\temp
del /f /q %userprofile%\recent\*.*
del /f /s /q "%userprofile%\recent\*.*"
echo -----------------------------------------
echo Complate!
echo
echo -----------------------------------------


