#!/bin/bash

#Input = single-end fasta/fastq files. FASTQ files will be converted to FASTA files; output is only FASTA.

# Chimera filtering

##########################################################
###Third-party applications:
#vsearch v2.17.0
    #citation: Rognes T, Flouri T, Nichols B, Quince C, Mahé F (2016) VSEARCH: a versatile open source tool for metagenomics PeerJ 4:e2584
    #Copyright (C) 2014-2021, Torbjorn Rognes, Frederic Mahe and Tomas Flouri
    #Distributed under the GNU General Public License version 3 by the Free Software Foundation
    #https://github.com/torognes/vsearch
#seqkit v0.15.0
    #citation: Shen W, Le S, Li Y, Hu F (2016) SeqKit: A Cross-Platform and Ultrafast Toolkit for FASTA/Q File Manipulation. PLOS ONE 11(10): e0163962. https://doi.org/10.1371/journal.pone.0163962
    #Distributed under the MIT License
    #Copyright © 2016-2019 Wei Shen, 2019 Oxford Nanopore Technologies.
    #https://bioinf.shenwei.me/seqkit/
#pigz v2.4
#perl v5.32.0
##########################################################

###############################
###############################
#These variables are for testing (DELETE when implementing to PipeCraft)
extension=$"fq"
#mandatory options
id=$"--id 0.97"                    # float (0-1)
minuniquesize=$"--minuniquesize 1" #pos int
#additional options
cores=$"--threads 4"               # pos int
abskew=$"--abskew 2"               # pos int
minh=$"--minh 0.28"                # float (0-1)

#reference_based=$"undefined"
denovo=$"TRUE"                #undefined or TRUE
#reference_based=$"/home/sten/Downloads/uchime_reference_dataset_28.06.2017/ITS1_ITS2_datasets/uchime_reference_dataset_ITS2_28.06.2017.fasta" #or 'undefined', if selection is not active
reference_based=$"undefined"
###############################
###############################

#############################
### Start of the workflow ###
#############################
#additional options, if selection != undefined
if [[ $reference_based == "undefined" ]]; then
    :
else
    database=$reference_based
fi
if [[ $denovo == "undefined" ]]; then
    :
else
    denovo_filt=$"TRUE"
fi

start=$(date +%s)
# Source for functions
source /scripts/framework.functions.sh

#output dir
output_dir=$"chimera_Filtered_out"
### Check if files with specified extension exist in the dir
first_file_check
### Prepare working env and check paired-end data
prepare_SE_env
#make output dir for CHIMERAS
mkdir $output_dir/chimeras
### Process samples
for file in *.$extension; do
    ### Make temporary directory for temp files (for each sample)
    if [ -d tempdir ]; then
        rm -rf tempdir
    fi 
    mkdir tempdir
    #Read file name; without extension
    input=$(echo $file | sed -e "s/.$extension//")
    ## Preparing files for the process
    printf "\n____________________________________\n"
    printf "Processing $input ...\n"
    #If input is compressed, then decompress (keeping the compressed file, but overwriting if filename exists!)
        #$extension will be $newextension
    check_gz_zip_SE
    ### Check input formats (fastq/fasta supported)
    check_extension_fastx

    #If input is FASTQ then convert to FASTA
    if [[ $newextension == "fastq" ]] || [[ $newextension == "fq" ]]; then
        checkerror=$(seqkit fq2fa -t dna --line-width 0 $input.$newextension -o $input.fasta 2>&1)
        check_app_error
        printf "Note: converted $newextension to FASTA \n"

        newextension=$"fasta"
        export newextension
        was_fastq=$"TRUE"
        export was_fastq
    fi

    ###############################
    ### Start chimera filtering ###
    ###############################
    #dereplicate sequences
    if [[ $denovo_filt == "TRUE" ]]; then
        checkerror=$(vsearch --derep_fulllength $input.$newextension \
        $minuniquesize \
        --sizein --sizeout \
        --fasta_width 0 \
        --uc tempdir/$input.dereplicated.uc \
        --output tempdir/$input.derep.fasta 2>&1)
        check_app_error

        #pre-cluster sequences; sorts seqs automaticcaly by decreasing abundance
        checkerror=$(vsearch --cluster_size tempdir/$input.derep.fasta \
        $cores \
        $id \
        --strand both \
        --sizein --sizeout \
        --fasta_width 0 \
        --uc tempdir/$input.preclustered.uc \
        --centroids tempdir/$input.preclustered.fasta 2>&1)
        check_app_error

        #search chimeras
        checkerror=$(vsearch --uchime_denovo tempdir/$input.preclustered.fasta \
        $abskew \
        $minh \
        --sizein \
        --sizeout \
        --fasta_width 0 \
        --chimeras $output_dir/chimeras/$input.denovo.chimeras.fasta \
        --nonchimeras tempdir/$input.denovo.nonchimeras.fasta 2>&1)
        check_app_error

        if [[ $reference_based == "undefined" ]]; then
            #Extract all non-chimeric sequences and add to $output_dir
            checkerror=$(vsearch --usearch_global $input.fasta \
            -db tempdir/$input.denovo.nonchimeras.fasta \
            --sizein --xsize \
            $id \
            --strand both \
            --fasta_width 0 \
            --matched $output_dir/$input.denovo.nonchimeras.fasta 2>&1)
            check_app_error

            #If input was fastq, then move all converted FASTA files to $output_dir/FASTA
            if [[ $newextension == "fastq" ]] || [[ $newextension == "fq" ]]; then
                mkdir -p $output_dir/FASTA
                mv $input.fasta $output_dir/FASTA
            fi

        else
            checkerror=$(vsearch --uchime_ref tempdir/$input.denovo.nonchimeras.fasta \
            $cores \
            --db $database \
            --sizein \
            --sizeout \
            --fasta_width 0 \
            --chimeras $output_dir/chimeras/$input.ref.chimeras.fasta \
            --nonchimeras tempdir/$input.ref.denovo.nonchimeras.fasta 2>&1)
            check_app_error

            #Extract all non-chimeric sequences
            checkerror=$(vsearch --usearch_global $input.fasta \
            -db tempdir/$input.ref.denovo.nonchimeras.fasta \
            --sizein --xsize \
            $id \
            --strand both \
            --fasta_width 0 \
            --matched $output_dir/$input.ref.denovo.nonchimeras.fasta 2>&1)
            check_app_error

            #If input was fastq, then move all converted FASTA files to $output_dir/FASTA
            if [[ $was_fastq == "TRUE" ]]; then
                mkdir -p $output_dir/FASTA
                mv $input.fasta $output_dir/FASTA
            fi
        fi
    
    else #only reference based chimera filtering
        checkerror=$(vsearch --uchime_ref $input.fasta \
        $cores \
        --db $database \
        --sizein \
        --sizeout \
        --fasta_width 0 \
        --chimeras $output_dir/chimeras/$input.ref.chimeras.fasta \
        --nonchimeras $output_dir/$input.ref.nonchimeras.fasta 2>&1)
        check_app_error

        #If input was fastq, then move all converted FASTA files to $output_dir/FASTA
        if [[ $was_fastq == "TRUE" ]]; then
            mkdir -p $output_dir/FASTA
            mv $input.fasta $output_dir/FASTA
        fi
    fi
done

#################################################
### COMPILE FINAL STATISTICS AND README FILES ###
#################################################
printf "\nCleaning up and compiling final stats files ...\n"
#file identifier string after the process
if [[ $reference_based == "undefined" ]]; then
    outfile_addition=$"denovo.nonchimeras"
elif [[ $denovo == "undefined" ]]; then
    outfile_addition=$"ref.nonchimeras"
else
    outfile_addition=$"ref.denovo.nonchimeras"
fi

clean_and_make_stats

#Make README.txt file
printf "Files in /$output_dir directory represent chimera filtered sequences.
Files in $output_dir/chimeras directory represent identified putative chimeric sequences.
In input was FASTQ formatted file(s), then it was converted to FASTA, and only FASTA is outputted.
\n" > $output_dir/README.txt

#Done
printf "\nDONE\n"
printf "Data in directory '$output_dir'\n"
printf "Summary of sequence counts in '$output_dir/seq_count_summary.txt'\n"
printf "Check README.txt files in output directory for further information about the process.\n"

end=$(date +%s)
runtime=$((end-start))
printf "Total time: $runtime sec.\n\n"

#variables for all services
echo "workingDir=/$output_dir"
echo "fileFormat=$newextension"
echo "dataFormat=$dataFormat"
echo "readType=single-end"