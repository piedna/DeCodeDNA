#!/bin/bash
##script written to convert the EFPQ bases that were converted by ONTBarcoder
##NOTE that this is an expected behaviour of ONTBarcoder:
	#https://github.com/asrivathsan/ONTbarcoder/issues/2
	
	#rename the files
#rename 's/.fa/.fasta/' *.fa

for i in *.fa

	do
	
	sed -i 's/E/A/g' $i
	sed -i 's/F/G/g' $i
	sed -i 's/Q/C/g' $i
	sed -i 's/P/T/g' $i
	
	done
