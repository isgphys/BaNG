BaNG Wipe Strategy and Long-Time Backups
========================================

BaNG supports keeping a given number of daily/weekly/monthly backups. This allows to keep certain backups that are several months old, without having to store all intermediate dates.

The number of backups to keep for each type can be configured:

```yaml
WIPE_KEEP_DAILY:   31
WIPE_KEEP_WEEKLY:   8
WIPE_KEEP_MONTHLY:  9
```

This example means that BaNG will start by filling 31 daily snapshots, then keep 8 backups separated by a week and finally 9 monthly snapshots. Notice that the first weekly backup is not taken after 7 days with respect to the present date, but rather to the oldest of the daily backups. Therefore the above example corresponds to a total period of 31 days + 8 weeks + 9 months = 1 year.

Schematically:

    present ---------------------------- past
    |  31 daily  |  8 weekly  |  9 monthly  |

Various wipe scenarios are documented in the test file `t/020_bang_wipe.t`.

The [restore](/restore) view shows the total number of backups, as well as the detailed list of available backups for each type.
