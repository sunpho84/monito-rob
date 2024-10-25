#!/bin/bash

export failureRate=0.12
export pendingTime=10
export runningTime=15

echo "             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)" > slurmStatus

rm -fr {failed,finished}Logs
rm -fr out_tw_25_s

listConfs=($(grep NGaugeConf input_tw_25_s -A 1000|grep -v NGaugeConf|awk '{print $1}'))
listOut=($(grep NGaugeConf input_tw_25_s -A 1000|grep -v NGaugeConf|awk '{print $2}'))

#provides a mock squeue environment
squeue ()
{
    cat slurmStatus
}

scancel ()
{
    awk '$1!='$1'' slurmStatus > tmp
    mv tmp slurmStatus
}

sbatch ()
{
    list=$(echo $1|sed 's|sbatch||;s|--array=||;s|,| |g'|awk '{print $0}')
    for j in $list
    do
	echo $RANDOM$RANDOM $j $jobName $PWD/$scriptFile PENDING
    done|awk 'BEGIN{srand()}{print $0,int(rand()*'$pendingTime')}' >> slurmStatus
    
    echo "Launched list: $list"
}

export -f squeue sbatch

while [ ! -f stopTest ]
do
      bash monitor.sh scr_tw_25_s.sh 
      sleep 1
      
      rm -f list{Failed,Finished,Started}
      touch list{Failed,Finished,Started}
      
      awk \
	  '{running=$(NF-1)=="RUNNING"}
	  {finished=running && $NF==0}
	  {failed=running && !finished && rand()<'$failureRate'}
	  $(NF-1)=="PENDING" && $NF==0{$(NF-1)="RUNNING";$NF=int(rand()*'$runningTime');print $1"@"$2 > "listStarted"}
	  {$NF=$NF-1}
	  failed{print $1"@"$2 > "listFailed"}
	  !finished && !failed{print $0}
	  finished{print $1"@"$2 > "listFinished"}' slurmStatus > tmp
      mv tmp slurmStatus

      for i in $(cat listStarted)
      do
	  n=($(echo $i|sed 's|@| |'))
	  jobid=${n[0]}
	  confid=${n[1]}
	  
	  o=${listOut[$confid]}
	  mkdir -p $o
	  
	  echo "Opening file: ${listConfs[$confid]}" > B48_tw_25s_Kl3.$jobid.out
	  touch $o/running_tw_25_s
      done

      for i in $(cat listFinished)
      do
	  n=($(echo $i|sed 's|@| |'))
	  jobid=${n[0]}
	  confid=${n[1]}

	  o=${listOut[$confid]}

	  echo "Ciao" >> B48_tw_25s_Kl3.$jobid.out
	  touch $o/finished_tw_25_s

      done
done
