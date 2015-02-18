Terminology
===========

Primary ID
----------

The atomic unit of BaNG is a single rsync command. The summary output of every rsync command is written as a row to the database, where it is uniquely identified by its primary ID.


Task ID
-------

Each call of a BaNG command gets assigned a unique task ID (microsecond timestamp). It then typically executes multiple rsync commands, that will all share the same task ID. Grouping database entries by task ID therefore summarizes individual BaNG tasks. As the crontab is a list of such BaNG tasks, such a grouping is in particular helpful to analyze the scheduling.


Job ID
------

The purpose of the job ID is to be able to group different rsync commands when using subfolder threading. For consistency, we also assign a job ID when not using subfolder threading. Grouping database entries by job ID collapses subfolder threads of individual source folders.


RealRuntime
-----------

Wall-clock time of the parallelized rsync. It is the actual time that elapses between the start and the end of a backup task with several threads in parallel.


TotalRuntime
------------

Wall-clock time of the serialized rsync. It is the time that would elapse, if all individual rsyncs were executed one after the other, without any parallelization.
