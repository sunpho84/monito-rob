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
	echo "Logfile $f has correctly finished, moving it to $finishedLogsDir"
	mv $f finishedLogs
    else
	nmins=$((($(date +%s)-$(stat -c %Y $f))/60))
	
	if [ $nmins -ge $nminsBeforeHang ]
	then
	    echo "The logfile: \"$f\" for job $id has hanged as it is not updated since $nmins mins, above the threshold $nminsBeforeHang"
	    
	    confFile=$(tac $f|grep -m 1 "Opening file:"|awk '{print $3}')
	    
	    if [ -z "$confFile" ]
	    then
		echo "Failed to detect last running conf"
	    else
		echo "Corresponding conf: $confFile"
		
		if [ ! -f "$confFile" ]
		then
		    echo "Conf: $confFile not existing, skipping it"
		else
		    outDir=$(grep $confFile $inputFile|awk '{print $2}')

		    if [ -z "$outDir" ]
		    then
			echo "Unable to find the conf $confFile in the input, very weird, skipping it"

			else 
			    if [ ! -f "$outdir" ]
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
					rm $runFile
				    else
					echo "Running file $runFile not found, no need to remove it"
				    fi
				fi
			    fi
		    fi
		fi
	    fi
	    
	    echo "Moving logfile $f into broken log files"
	    mv $f $failedLogsDir
	fi
    fi
    echo -----
done
