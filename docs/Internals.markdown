Internals
=========

JobStatus Codes
----------------

These are BaNG internally used code numbers.

### Pre Queuing

| Code  | Name      | Note      |
| :---: | :---      | :---      |
| -2    | *Remote Shell not working* | evaluated by check_client_rshell_connection() |
| -1    | *Host offline* | evaluated by check_client_connection() |

### Post Queuing

| Code  | Name      | Note      |
| :---: | :---      | :---      |
|  0    | *Backup currently running* | |
|  1    | *Rsync done* | rsync is finished but still waiting for finishing the task |
|  2    | *forked Job done* | everything worked well, task is finished |

---

ErrStatus Codes
---------------

These are return codes from rsync, see **`man rsync`**

| Code  | Name          | Note      |
| :---: | :---          | :---      |
|  0    | *Success*     |  |
|  12   | *Error in rsync protocol data stream*  |   |
|  23   | *Partial transfer due to error* |  |
|  24   | *Partial transfer due to vanished source files* |   |

Following additionaly BaNG internally used code numbers

| Code  | Name          | Note      |
| :---: | :---          | :---      |
|  99   | *no last_bkp* | used by bangstat_recentbackups() if no recent backup available |
