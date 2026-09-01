#!/bin/bash

#
# checkRun.sh -- did every job in a PEMapper run succeed, and if not,
# which ones failed?
#
# usage:
#   checkRun.sh                  check every run under ./SLURM.PEMAP
#   checkRun.sh RUNDIR ...       check the named run directories
#   checkRun.sh SLURM.PEMAP      check every run under a parent directory
#   checkRun.sh -o FILE ...      write the report to FILE as well as stdout
#
# exit status:
#   0   every job completed
#   1   something failed, or a job's fate could not be determined
#   2   nothing has failed but jobs are still queued or running
#
# LSF appended an epilogue to every job log, so grepping the log tree
# answered "did that run work?". Slurm writes nothing of its own into the
# -o file: a job that was OOM-killed, timed out or exited non-zero leaves
# a log that can look identical to a good one. Two records replace the
# epilogue, and this script reads both:
#
#   $RUNDIR/jobs.tsv    every job id QRUN submitted for the run. Without
#                       it the jobs are not even findable after the fact.
#                       sacct is then the authority on what became of
#                       each one -- it is the only source that sees a job
#                       the scheduler killed outright.
#
#   #PEMAP_EXIT=<rc>    a trailer QRUN appends to every job log. Used
#                       here only as a fallback, for runs old enough that
#                       sacct has purged the accounting record. An absent
#                       trailer is itself a signal: the job never reached
#                       the end of its script.
#

usage () {
    echo
    echo "usage: checkRun.sh [-o REPORT] [RUNDIR ...]"
    echo
    echo "  with no RUNDIR, checks every run under ./SLURM.PEMAP"
    echo "  exit: 0 all ok, 1 failures, 2 still running"
    echo
    exit 1
}

REPORT=""
while getopts "o:h" opt; do
    case $opt in
        o)
            REPORT=$OPTARG
            ;;
        h)
            usage
            ;;
        \?)
            usage
            ;;
    esac
done

shift $((OPTIND - 1))

if [ "$#" -eq 0 ]; then
    set -- SLURM.PEMAP
fi

##
# An argument is either a run directory (it holds jobs.tsv) or a parent
# of run directories, which is what makes the no-argument scan and a
# whole batch from runPEMapperMultiDirectories.sh work the same way.

RUNDIRS=""
for ARG in "$@"; do
    if [ -e "$ARG/jobs.tsv" ]; then
        RUNDIRS="$RUNDIRS $ARG"
    elif [ -d "$ARG" ]; then
        for RDIR in "$ARG"/*; do
            if [ -e "$RDIR/jobs.tsv" ]; then
                RUNDIRS="$RUNDIRS $RDIR"
            fi
        done
    else
        echo "checkRun.sh: no such run directory [$ARG]" >&2
    fi
done

checkOneRun () {

    RUNDIR=$1

    SAMPLE=""
    SUBMIT_COMPLETE=""
    DRYRUN=""
    if [ -e $RUNDIR/RUNINFO ]; then
        SAMPLE=$(sed -n 's/^SAMPLE=//p' $RUNDIR/RUNINFO)
        SUBMIT_COMPLETE=$(sed -n 's/^SUBMIT_COMPLETE=//p' $RUNDIR/RUNINFO)
        DRYRUN=$(sed -n 's/^DRYRUN=//p' $RUNDIR/RUNINFO)
    fi

    echo "== $(basename $RUNDIR)${SAMPLE:+  [$SAMPLE]}"

    if [ "$DRYRUN" != "" ]; then
        echo "   SKIP     dry run, nothing was submitted"
        return 3
    fi

    #
    # The __08__STATUS job reports on the run, so it is not part of what
    # is being reported on. When this *is* that job it is necessarily
    # still RUNNING and would mask the verdict; run afterwards by hand it
    # would show FAILED, since checkRun.sh exits non-zero on a failed
    # run, and that would read as a second, phantom failure.
    #
    IDS=$(awk -F'\t' -v me="$SLURM_JOB_ID" \
              '/^#/{next} NF>0 && $1!=me && $2 !~ /__08__STATUS$/ {print $1}' \
              $RUNDIR/jobs.tsv | tr '\n' ',' | sed 's/,$//')

    if [ "$IDS" == "" ]; then
        echo "   FAILED   no job ids recorded in $RUNDIR/jobs.tsv"
        return 1
    fi

    #
    # -X keeps this to the allocation and drops the .batch/.extern rows.
    # State is the field that matters: an OOM kill reports COMPLETED-
    # looking ExitCodes (0:125) while State says OUT_OF_MEMORY.
    #
    SACCT=$(sacct -X -n -P -j "$IDS" \
                --format=JobID,State,ExitCode,Elapsed 2>/dev/null | tr '|' '\t')

    JOBREPORT=$(awk -F'\t' -v me="$SLURM_JOB_ID" -v rundir="$RUNDIR" '

        #
        # Fallback for jobs sacct no longer knows about. The trailer is
        # the last thing the job script writes, but slurmd can append an
        # OOM notice after it, so look at the tail rather than line 1.
        #
        function trailer(logf,   cmd, line, rc) {
            rc = ""
            cmd = "tail -20 \"" logf "\" 2>/dev/null"
            while ((cmd | getline line) > 0) {
                if (match(line, /#PEMAP_EXIT=[0-9]+/)) {
                    rc = substr(line, RSTART + 12, RLENGTH - 12)
                }
            }
            close(cmd)
            return rc
        }

        NR == FNR {
            # sacct: JobID State ExitCode Elapsed. "CANCELLED by 12345"
            # carries the canceling uid, so keep the first word only.
            split($2, s, " ")
            state[$1] = s[1]
            code[$1] = $3
            secs[$1] = $4
            next
        }

        /^#/ { next }
        NF == 0 { next }
        $1 == me { next }
        $2 ~ /__08__STATUS$/ { next }

        {
            id = $1
            name = $2

            #
            # The manifest records an absolute log path, which is wrong
            # as soon as a run directory is copied or moved. Prefer the
            # log sitting in the directory being checked and keep the
            # recorded path only as a fallback.
            #
            logf = rundir "/" id ".out"
            if ((getline probe < logf) < 0) {
                close(logf)
                logf = $3
            } else {
                close(logf)
            }

            st = state[id]
            if (st == "") {
                rc = trailer(logf)
                if (rc == "0") {
                    st = "COMPLETED"
                    code[id] = "0:0"
                } else if (rc != "") {
                    st = "FAILED"
                    code[id] = rc ":0"
                } else {
                    st = "NO-RECORD"
                }
                secs[id] = "-"
            }

            njob++

            if (st == "COMPLETED") {
                nok++
                next
            }

            if (st ~ /^(PENDING|RUNNING|SUSPENDED|COMPLETING|CONFIGURING|REQUEUED|RESIZING|SIGNALING|STAGE_OUT)$/) {
                npend++
                pending[npend] = sprintf("   %-10s %-12s %s", id, st, name)
                next
            }

            #
            # A CANCELLED job is almost always the downstream casualty of
            # --kill-on-invalid-dep, not a fault of its own. Keeping the
            # two apart is what stops one real failure from printing as
            # eight, and puts the root cause first.
            #
            if (st == "CANCELLED") {
                ncancel++
                cancelled[ncancel] = sprintf("   %-10s %-12s %s", id, st, name)
                next
            }

            nfail++
            failed[nfail] = sprintf("   %-10s %-14s %-8s %-10s %s\n             %s", \
                                    id, st, code[id], secs[id], name, logf)
        }

        END {
            counts = nok " ok"
            if (nfail)   { counts = counts ", " nfail " failed" }
            if (ncancel) { counts = counts ", " ncancel " cancelled" }
            if (npend)   { counts = counts ", " npend " running/queued" }

            if (nfail == 0 && ncancel == 0 && npend == 0) {
                printf("   OK       %d/%d jobs completed\n", nok, njob)
                exit 0
            }

            if (nfail == 0 && ncancel == 0) {
                printf("   RUNNING  %d jobs: %s\n", njob, counts)
                for (i = 1; i <= npend; i++) { print pending[i] }
                exit 2
            }

            printf("   FAILED   %d jobs: %s\n", njob, counts)

            if (nfail) {
                print "   ---- failed"
                for (i = 1; i <= nfail; i++) { print failed[i] }
            }
            if (ncancel) {
                printf("   ---- cancelled downstream (%d)\n", ncancel)
                for (i = 1; i <= ncancel; i++) { print cancelled[i] }
            }
            if (npend) {
                printf("   ---- still running (%d)\n", npend)
                for (i = 1; i <= npend; i++) { print pending[i] }
            }
            exit 1
        }

    ' <(printf '%s\n' "$SACCT") $RUNDIR/jobs.tsv)

    RC=$?

    #
    # QRUN exits the whole of pipe.sh when an sbatch fails, which leaves
    # the jobs it had already submitted running and the rest of the graph
    # never submitted. Those jobs can all succeed, so without this marker
    # a truncated run reports OK. This has to lead the report: the job
    # counts below it are only the jobs that made it out of pipe.sh.
    #
    if [ "$SUBMIT_COMPLETE" == "" ]; then
        if [ "$RC" == "2" ]; then
            echo "   NOTE     no SUBMIT_COMPLETE yet; pipe.sh may still be submitting"
        else
            echo "   FAILED   pipe.sh never finished submitting this run (no SUBMIT_COMPLETE)"
            echo "            of the jobs it did submit:"
            RC=1
        fi
    fi

    echo "$JOBREPORT"

    return $RC
}

checkAllRuns () {

    NRUN=0
    NOK=0
    NFAIL=0
    NRUNNING=0
    NSKIP=0
    WORST=0

    for RUNDIR in $RUNDIRS; do

        checkOneRun $RUNDIR
        RC=$?

        NRUN=$((NRUN + 1))
        case $RC in
            0)
                NOK=$((NOK + 1))
                ;;
            3)
                # dry run: neither a pass nor a failure
                NSKIP=$((NSKIP + 1))
                ;;
            2)
                NRUNNING=$((NRUNNING + 1))
                if [ "$WORST" == "0" ]; then
                    WORST=2
                fi
                ;;
            *)
                NFAIL=$((NFAIL + 1))
                WORST=1
                ;;
        esac

    done

    if [ "$NRUN" -gt 1 ]; then
        echo
        SKIPPED=""
        if [ "$NSKIP" -gt 0 ]; then
            SKIPPED=", $NSKIP SKIPPED"
        fi
        echo "---- $NRUN runs: $NOK OK, $NFAIL FAILED, $NRUNNING RUNNING$SKIPPED"
    fi

    if [ "$WORST" == "0" ] && [ "$NSKIP" == "$NRUN" ]; then
        # nothing but dry runs; saying OK would overstate it
        return 3
    fi

    return $WORST
}

if [ "$RUNDIRS" == "" ]; then
    echo "PEMAP STATUS: NONE   no run directories found"
    exit 1
fi

BODY=$(checkAllRuns)
RC=$?

case $RC in
    0)
        VERDICT=OK
        ;;
    2)
        VERDICT=RUNNING
        ;;
    3)
        VERDICT=SKIP
        RC=0
        ;;
    *)
        VERDICT=FAILED
        ;;
esac

printReport () {
    echo "PEMAP STATUS: $VERDICT   $(date '+%Y-%m-%d %H:%M:%S')"
    echo "$BODY"
}

if [ "$REPORT" != "" ]; then
    printReport | tee $REPORT
else
    printReport
fi

exit $RC
