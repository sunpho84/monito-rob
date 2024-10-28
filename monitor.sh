#!/bin/bash

#control parameters
nminsBeforeHang=5
finishedLogsDir=finishedLogs
failedLogsDir=failedLogs

#check the arguments
if [ -z "$1" ]
then
    echo "Use: $0 [scriptfile]"
    exit 0
fi

if ! command -v maybe 2>&1 >/dev/null
then
    maybe=echo
    echo "Dry-run. Launch with: with maybe= $@"
fi

#check the existence of the script file
scriptFile=$1
if [ ! -f "$scriptFile" ]
then
    echo "Scriptfile \"$scriptFile\" absent"
    exit 0
fi

#print the file collapsing newlines
printFile ()
{
    sed ':a;N;$!ba;s/\\\n//g' "$scriptFile"|grep -v \#\#SBATCH
}

getSbatchArg ()
{
    tmp=$(printFile|grep \#|grep SBATCH|grep -- $1|tail -n 1|sed  's| \?||g'|sed 's|#SBATCH'$1'=\?||')
    
    if [ -z "$tmp" ]
    then
	echo "Unable to find option \"$1\" in the script"
	exit
    fi
    
    echo $tmp
}

#finds the job name
jobName=$(getSbatchArg --job-name)

#finds the walltime
walltime=$(getSbatchArg --time)

#converts the walltime in s
walltimeInS=$(echo $walltime|sed 's|:| |g'|awk '{s=$NF}NF>1{m=$(NF-1)}NF>2{h=$(NF-2)}NF>3{d=$(NF-3)}END{print s+60*(m+60*(h+24*d))}')

#finds the template for the log file
logTemplate=$(getSbatchArg --output)

if ! echo "$logTemplate"|grep -q %j
then
    echo "The template for the logfiles, \"$logTemplate\" does not contain the %j string, don't know how to process it"
    exit
fi

#create logfiles dir
mkdir -p $finishedLogsDir $failedLogsDir

#splits the template into prefix and suffix
tmp=($(echo $logTemplate|sed 's|%j| |'))
logTemplatePref=${tmp[0]}
logTemplateSuff=${tmp[1]}

#check the splitting
if [ "${logTemplatePref}%j${logTemplateSuff}" != "$logTemplate" ]
then
    echo "Template logfile $logTemplate failed to be split, result prefix: $logTemplatePref, suffix: $logTemplateSuff"
    exit
fi

#finds the command
if ! command=$(printFile|grep "mpirun\|srun")
then
    echo "Unable to find the \"srun\" or \"mpirun\" command in the scrip file: $scriptFile"
    exit 0
fi

#finds the input file
for i in $command
do
    if [ -f $i ]
    then
	inputFile=$i
    else
	if [ ! -z $inputFile ]
	then
	    suff=_$i
	fi
    fi
done

#check that the input file has been found
if [ -z "$inputFile" ]
then
    echo "None of the arguments of the run command: \"$command\" seems input files"
    exit 0
fi

archiveFinishedLog ()
{
    echo "Logfile $1 has correctly finished, moving it to $finishedLogsDir"
    $maybe mv $f finishedLogs
}

cleanOutDirOfConf ()
{
    outDir=$(grep $confFile $inputFile|awk '{print $2}')
	    
    if [ -z "$outDir" ]
    then
	echo "Unable to find the conf $confFile in the input, very weird, skipping it"
	
    else 
	if [ ! -f "$outDir" ]
	then
	    echo "Output dir: $outDir not existing, skipping the conf"
	    
	    finishedFile=$outDir/finished$suff
	    if [ -f  ]
	    then
		echo "The conf $confFile has finished as the $finishedFile exists, skipping the conf"
	    else
		echo "The conf $confFile has not yet finished"
		
		runFile=$outDir/running$suff
		
		if [ -f "$runFile" ]
		then
		    echo "Running file $runFile found, removing it"
		    $maybe rm $runFile
		else
		    echo "Running file $runFile not found, no need to remove it"
		fi
	    fi
	fi
    fi
}

archiveBrokenLog ()
{
    echo "The logfile: \"$1\" for job $id has hanged as it has not updated since $nmins mins, above the threshold $nminsBeforeHang"
    
    confFile=$(tac $1|grep -m 1 "Opening file:"|awk '{print $3}')
    
    if [ -z "$confFile" ]
    then
	echo "Failed to detect last running conf"
    else
	echo "Corresponding conf: $confFile"
	
	if [ ! -f "$confFile" ]
	then
	    echo "Conf: $confFile not existing, skipping it"
	else
	    cleanOutDirOfConf "$confFile"
	fi
    fi

    echo "Moving logfile $f into broken log files"
    $maybe mv "$1" "$failedLogsDir"
}

purgeJob ()
{
    if squeue --me|awk '$1==$1'|grep $1 > /dev/null 2>&1
    then
	echo "Job $1 is running, killing it"
	$maybe scancel $1
    fi
}

#run on all logfiles
for f in $(ls $logTemplatePref*$logTemplateSuff 2> /dev/null)
do
    #gets the id
    id=$(echo $f|sed 's|'$logTemplatePref'||;s|'$logTemplateSuff'||')
    [ -n "$id" ] && [ "$id" -eq "$id" ] 2>/dev/null
    if [ $? -ne 0 ]; then
	echo "Id: $id of logfile $f extracted according to template $logTemplate is not number"
	exit
    fi
    
    #deal with finished jobs
    if tail -n 200 $f|grep -q Ciao
    then
	archiveFinishedLog $f
    else
	nmins=$((($(date +%s)-$(stat -c %Y $f))/60))
	
	if [ $nmins -ge $nminsBeforeHang ]
	then
	    archiveBrokenLog $f
	    
	    purgeJob $id
	else
	    echo "Logfile $f has not finished and not old, last update is of $nmins mins, leaving it run for at least another $(($nminsBeforeHang-$nmins)) mins"
	fi
    fi
    echo -----
done

#gets the list of queued or running jobs
launchedList=$(squeue --me --array --Format ArrayJobID,ArrayTaskID,command:200|grep $PWD/$scriptFile|awk '{print $2}')
nLaunched=$(echo $launchedList|wc -w)
echo "Currently launched: $nLaunched jobs"

#gets the number of configurations
nconfs=$(grep NGaugeConf $inputFile|awk '{print $NF}')

#creates the list to launch
listToPossibleLaunch=""
n=0
for i in $(cat -s $inputFile|grep NGaugeConf -A $nconfs|grep -v NGaugeConf|awk '{print $2}')
do
    if [ ! -f "$i/finished$suff" ]
    then
	listToPossibleLaunch="$listToPossibleLaunch $n"
    fi
    
    ((n++))
done

#creates the command args
div=""
listToLaunch=""
for j in $(for i in $launchedList $listToPossibleLaunch
	   do
	       echo $i
	   done|sort -g|uniq -u)
do
    listToLaunch="$listToLaunch$div$j"
    div=","
done

#report the number of jobs to launch
nToLaunch=$(echo $listToLaunch|sed 's|,| |g'|wc -w)
echo "Going to launch: $nToLaunch jobs"

#launch
if [ "$nToLaunch" -gt 0 ]
then
    $maybe sbatch --array="$listToLaunch" $scriptFile
fi
