#!/usr/bin/env python3
import sys
import pty
import os
import re

def run_test(script_cmd):
    master, slave = pty.openpty()
    pid = os.fork()
    if pid == 0:
        # Child
        os.close(master)
        os.setsid()
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        os.close(slave)
        os.execvp(script_cmd[0], script_cmd)
    else:
        # Parent
        os.close(slave)
        buf = ""
        stage = 0
        while True:
            try:
                data = os.read(master, 1024).decode('utf-8', errors='ignore')
                if not data:
                    break
                buf += data
                # Stage 0: Wait for drive prompt, send empty enter then '9' then '1'
                if stage == 0 and "Select drive to backup" in buf:
                    os.write(master, b"\n")
                    stage = 1
                elif stage == 1 and "Empty input" in buf:
                    os.write(master, b"9\n")
                    stage = 2
                elif stage == 2 and "Invalid option" in buf:
                    os.write(master, b"1\n")
                    stage = 3
                # Stage 3: Scope selection -> send '1'
                elif stage == 3 and "Select partition scope" in buf:
                    os.write(master, b"1\n")
                    stage = 4
                # Stage 4: Default image name -> press Enter
                elif stage == 4 and "Enter image folder name" in buf:
                    os.write(master, b"\n")
                    stage = 5
                # Stage 5: Engine selection -> select Clonezilla (1)
                elif stage == 5 and "Select imaging engine" in buf:
                    os.write(master, b"1\n")
                    stage = 6
                # Stage 6: Rescue Mode -> select Rescue Mode (2)
                elif stage == 6 and "Select Rescue Mode" in buf:
                    os.write(master, b"2\n")
                    stage = 7
                # Stage 7: Pre-flight confirmation -> send empty enter then 'n'
                elif stage == 7 and "Start backup operation now? (y/n):" in buf:
                    os.write(master, b"\n")
                    stage = 8
                elif stage == 8 and "Empty response" in buf:
                    os.write(master, b"n\n")
                    stage = 9
            except OSError:
                break
        os.waitpid(pid, 0)
        print("\n--- PTY RUNNER COMPLETED ---")
        if "Backup aborted by user" in buf:
            print("PASS: Verified full interactive pipeline & non-destructive abort.")
            sys.exit(0)
        else:
            print("FAIL: Pipeline did not reach non-destructive abort.")
            sys.exit(1)

if __name__ == "__main__":
    run_test(sys.argv[1:])
