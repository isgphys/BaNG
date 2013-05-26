  BaNG Database
=================

 Basics
--------

BaNG uses a **MySQL** database to store backup statistics.

View columns of table ```statistics``` in database ```bangstat```

    use bangstat;
    describe statistic;

Use profiling to view query statistics

    set profiling = 1;
    show profiles;
    show profile for query 1;

Change MySQL engine from ```MyISAM``` to ```InnoDB```

    ALTER TABLE mytable ENGINE = InnoDB;

 Views
-------

    CREATE OR REPLACE VIEW statistic_job_sum AS SELECT JobID, MIN(Start) as Start, MAX(Stop) as Stop,
    SUM(TIMESTAMPDIFF(Second, Start , Stop)) as Runtime,
    BkpFromHost, IF(isThread,SUBSTRING_INDEX(BkpFromPath,'/',(LENGTH(BkpFromPath)-LENGTH(REPLACE(BkpFromPath,'/','')))),
    BkpFromPath) as BkpFromPath, BkpToHost, BkpToPath, LastBkp, isThread = Null as isThread, JobStatus, BkpGroup,
    SUM(NumOfFiles) as NumOfFiles, SUM(NumOfFilesTrans) as NumOfFilesTrans, SUM(TotFileSize) as TotFileSize,
    SUM(TotFileSizeTrans) as TotFileSizeTrans
    FROM statistic
    WHERE Start > date_sub(NOW(), INTERVAL 100 DAY)
    GROUP BY JobID, LastBkp, bkptopath
    ORDER BY LastBkp;

    CREATE OR REPLACE VIEW statistic_job_thread AS SELECT JobID, Start, Stop, TIMESTAMPDIFF(Second, Start , Stop) as Runtime,
    BkpFromHost, BkpFromPath, BkpToHost, BkpToPath, LastBkp, isThread, JobStatus, BkpGroup,
    NumOfFiles, NumOfFilesTrans, TotFileSize, TotFileSizeTrans
    FROM statistic
    WHERE Start > date_sub(NOW(), INTERVAL 100 DAY)
    AND isThread = 1;

    CREATE OR REPLACE VIEW statistic_all AS SELECT * FROM statistic_job_sum UNION SELECT * FROM statistic_job_thread;

    CREATE OR REPLACE VIEW recent_backups AS SELECT JobID, MIN(Start) as Start, MAX(Stop) as Stop, BkpFromHost,
    IF(isThread,SUBSTRING_INDEX(BkpFromPath,'/',(LENGTH(BkpFromPath)-LENGTH(REPLACE(BkpFromPath,'/','')))),BkpFromPath) as BkpFromPath,
    BkpToHost, BkpToPath, LastBkp, isThread, BkpGroup, GROUP_CONCAT(DISTINCT ErrStatus order by ErrStatus) as ErrStatus, JobStatus
    FROM statistic
    WHERE Start > date_sub(NOW(), INTERVAL 100 DAY)
    GROUP BY JobID, LastBkp, bkptopath order by LastBkp;

    CREATE OR REPLACE VIEW recent_backups AS
    SELECT JobID, MIN(Start) as Start, MAX(Stop) as Stop, BkpFromHost,
    IF(isThread,SUBSTRING_INDEX(BkpFromPath,'/',(LENGTH(BkpFromPath)-LENGTH(REPLACE(BkpFromPath,'/','')))),BkpFromPath) as BkpFromPath,
    BkpToHost, BkpToPath, LastBkp, isThread, BkpGroup,
    GROUP_CONCAT(DISTINCT ErrStatus order by ErrStatus) as ErrStatus, JobStatus
    FROM statistic
    WHERE Start > date_sub(NOW(), INTERVAL 100 DAY)
    GROUP BY JobID, LastBkp, bkptopath order by LastBkp;

    CREATE OR REPLACE VIEW lastday_transfer AS
    SELECT SUM(NumOfFilesTrans) AS TotalNumFilesTrans, SUM(TotFileSizeTrans) AS TotalFileSizeTrans
    FROM statistic_all
    WHERE Start > date_sub(concat(curdate(),' 18:00:00'), interval 1 day)
    AND isThread is NULL
    AND BkpToHost like 'phd-bkp-gw'
    ORDER BY Start;
