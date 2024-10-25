#!/bin/bash

failureRate=0.12
runningTime=15
echo "             JOBID PARTITION     NAME     USER ST       TIME  NODES NODELIST(REASON)" > slurmStatus

rm -fr {failed,finished}Logs
rm -fr out_tw_25_s

listConfs=($(grep NGaugeConf input_tw_25_s -A 1000|grep -v NGaugeConf|awk '{print $1}'))
listOut=($(grep NGaugeConf input_tw_25_s -A 1000|grep -v NGaugeConf|awk '{print $2}'))

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
