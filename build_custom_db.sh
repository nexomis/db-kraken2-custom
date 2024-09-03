#!/usr/bin/bash

set -e

################
####  help  ####
################

function show_help() {
  cat << EOF
Usage: $0 -o <out_db_dir> [options]

Script to download genomic and transcriptomic sequences and build a Kraken2 database.

Input/Output Arguments:
Reminder: at least one of the parameters between gnom_acc_id/gnom_acc_name and library must be non-null and valid, otherwise there is no reference on which to create the database and therefore no database can be created.

  -i, (gnom_acc_id)    : NCBI RefSeq or Genbank accession ID(s), separated by commas if multiple. E.g., "GCF_000001405.40"
  -n, (gnom_acc_name)  : Corresponding name(s) for the accession IDs, separated by commas if multiple. E.g., "GRCh38.p14"
  -j, (taxid)          : Taxon id corresponding to element given in '-i' and '-n'.
                         If specified '--download-taxonomy' step (from 'kraken2-build') is runned in light mode ('--skip-maps'),
                         which avoids 40G of data to be stored and processed, of which several G are downloaded.
                         Note: maybe '--skip-maps' is not compatible with library 'plasmid' or 'nr' (see kraken2 documentation) ?
  -l, (library)        : Kraken2 library IDs, separated by commas if multiple.
                         Valid values are: 'archaea', 'bacteria', 'plasmid', 'viral', 'human', 'fungi', 'plant', 'protozoa', 'nr', 'nt', 'UniVec', 'UniVec_Core'.
  -o, (out_db_dir)     : [recquired] - Directory where the Kraken2 database will be created.
                         Should not exist unless 'force' is set to true.
  -f, (force)          : If set uto true, allows the script to proceed even if 'out_db_dir' already exists. Default 'false'
                         Be careful if 'out_db_dir' already exists and is not empty, because certain file types with the right path pattern
                        (e.g. custom fasta) will be included in the resulting database (this can be useful to resume incomplete excecution).
                        In addition, the contents of this directory can be overwritten or deleted. Default is false.
  -x, (taxonomy_db)    : Directory of an existing Kraken2 taxonomy database to link to the new database.
                         If specified '--download-taxonomy' step (from 'kraken2-build') is skipped (even if '-j' is specified !!).

Kraken2-Build Arguments:
to be incorporated as is into the command line concerned (to be provided between quotation)

  -a, (args_dl_tax)    : Additional arguments for the '--download-taxonomy' command.
  -b, (args_dl_lib)    : Additional arguments for the '--download-library' command.
  -c, (args_add_lib)   : Additional arguments for the '--add-to-library' command.
  -d, (args_build)     : Additional arguments for the '--build' command.

Other:

  -t, (threads)        : Number of threads to use for Kraken2 build. Default is 6.
  -s, (pre/post/all)   : Pre build or Post build only
  -h, (help)           : Display this help message and exit.


Examples:
  $0 -i GCF_000001405.40 -n GRCh38.p14 -o kraken2DB_GRCh38 -t 8 -l bacteria,plasmid -a "--use-ftp"
    or
  $0 -o kraken2DB_human -t 8 -l human
EOF
  exit 1
}

echo -e "\n\n#[$(date)]: START\n\n"

######################
####  parse args  ####
######################

# Initialize variables
force=false
threads=6
step=all

# Parse command-line options
while getopts ":i:n:j:o:f:l:t:a:b:c:d:x:s:h" opt; do
  case $opt in
    i) gnom_acc_id="$OPTARG" ;;
    n) gnom_acc_name="$OPTARG" ;;
    j) taxid="$OPTARG" ;;
    o) out_db_dir="$OPTARG" ;;
    f) force="$OPTARG" ;;    # f) force=true ;;
    l) library="$OPTARG" ;;
    t) threads="$OPTARG" ;;
    a) args_dl_tax="$OPTARG" ;;
    b) args_dl_lib="$OPTARG" ;;
    c) args_add_lib="$OPTARG" ;;
    d) args_build="$OPTARG" ;;
    x) taxonomy_db="$OPTARG" ;;
    s) step="$OPTARG" ;;
    h) show_help ;;
    \?) echo "Invalid option: -$OPTARG" >&2; show_help ;;
    :) echo "Option -$OPTARG requires an argument." >&2; show_help ;;
  esac
done

#########################
####  validate args  ####
#########################

if [ "$step" = "all" ] || [ "$step" = "pre" ]; then
  # recquired parameters
  if [[ -z ${out_db_dir} ]]; then
    echo "Error: 'out_db_dir' must be provided."
    exit 1
  fi

  if ( [[ -z ${gnom_acc_id} ]] || [[ -z ${gnom_acc_name} ]] ) && [[ -z ${library} ]]; then
    echo "Warning: Normally, if 'library' is not defined, 'gnom_acc_id' AND 'gnom_acc_name' should be defined (or vice-versa). The only exception is if you wish to use the fasta initially present in 'out_db_dir'."
    if [[ ${force} != true ]] || [[ ! -d ${out_db_dir} ]]; then
      echo "Error: but this strategy requires you to activate '-f' and 'out_db_dir' to already exist"
      exit 1
    fi
  fi

  if ( [[ -z ${gnom_acc_id} ]] && [[ -z ${gnom_acc_name} ]] ); then 
    args_dl_tax+=" --skip-maps"
  fi

  # Ensure out_db_dir does not exist unless force is true
  if [[ -d ${out_db_dir} ]] && [[ ${force} != true ]]; then
    echo "Error: Output directory '${out_db_dir}' already exists. Possible to use '-f' option, see help message."
    exit 1
  fi

  # Validate library values if provided
  valid_libraries=("archaea" "bacteria" "plasmid" "viral" "human" "fungi" "plant" "protozoa" "nr" "nt" "UniVec" "UniVec_Core")
  IFS=',' read -r -a library_array <<< "${library}"
  for lib in "${library_array[@]}"; do
    if [[ ! " ${valid_libraries[@]} " =~ " ${lib} " ]]; then
      echo "Error: Invalid library '${lib}'. Valid options are: ${valid_libraries[*]}."
      exit 1
    fi
  done


  ## Convert comma-separated lists to arrays
  IFS=',' read -r -a gnom_acc_id_array <<< "${gnom_acc_id}"
  IFS=',' read -r -a gnom_acc_name_array <<< "${gnom_acc_name}"
  IFS=',' read -r -a taxid_array <<< "${taxid}"

  ## Validate array lengths
  if [[ ${#gnom_acc_id_array[@]} -ne ${#gnom_acc_name_array[@]} ]]; then
    echo "Error: 'gnom_acc_id' and 'gnom_acc_name' must have the same number of elements."
    exit 1
  fi

  if [[ -n ${taxid} ]]; then
    args_dl_tax+=" --skip-maps"
    if [[ ${#taxid_array[@]} -ne ${#gnom_acc_id_array[@]} ]]; then
      echo "Error: 'taxid' and 'gnom_acc_id' must have the same number of elements."
      exit 1
    fi
  fi

  ########################
  ####  import fasta  ####
  ########################

  ## Download and process sequences
  mkdir -p "${out_db_dir}/library/add_custom_tmp/"
  for i in "${!gnom_acc_id_array[@]}"; do
    mkdir -p "${out_db_dir}/library/add_custom_download_tmp/"
    gnom_acc_id_i="${gnom_acc_id_array[$i]}"
    gnom_acc_name_i="${gnom_acc_name_array[$i]}"

    base_url="https://ftp.ncbi.nlm.nih.gov/genomes/all/${gnom_acc_id_i:0:3}/${gnom_acc_id_i:4:3}/${gnom_acc_id_i:7:3}/${gnom_acc_id_i:10:3}/${gnom_acc_id_i}_${gnom_acc_name_i}"
    if ! wget -q -O "${out_db_dir}/library/add_custom_download_tmp/genome_${gnom_acc_name_i}.fna.gz" \
      "${base_url}/${gnom_acc_id_i}_${gnom_acc_name_i}_genomic.fna.gz"; then
      echo "Error downloading genome ${gnom_acc_name_i}.fna.gz"
      exit 1
    fi

    if ! wget -q -O "${out_db_dir}/library/add_custom_download_tmp/rna_${gnom_acc_name_i}.fna.gz" \
      "${base_url}/${gnom_acc_id_i}_${gnom_acc_name_i}_rna_from_genomic.fna.gz"; then
      echo "Error downloading rna ${gnom_acc_name_i}.fna.gz"
    fi

    if [[ -z ${taxid} ]]; then    
      if ! zcat "${out_db_dir}/library/add_custom_download_tmp/genome_${gnom_acc_name_i}.fna.gz" \
        "${out_db_dir}/library/add_custom_download_tmp/rna_${gnom_acc_name_i}.fna.gz" \
        > "${out_db_dir}/library/add_custom_tmp/${gnom_acc_name_i}.fa"; then
        echo "Error concatenating files for ${gnom_acc_name_i}"
        exit 1
      fi
    else
      taxid_i="${taxid_array[$i]}"
      if ! zcat "${out_db_dir}/library/add_custom_download_tmp/genome_${gnom_acc_name_i}.fna.gz" \
        "${out_db_dir}/library/add_custom_download_tmp/rna_${gnom_acc_name_i}.fna.gz" \
        | sed -re "s/^>([^ ]*)(.*)$/>\1|kraken:taxid|${taxid_i}\2/" \
        > "${out_db_dir}/library/add_custom_tmp/${gnom_acc_name_i}.fa"; then
        echo "Error concatenating files for ${gnom_acc_name_i}"
        exit 1
      fi
    fi

    rm -rf "${out_db_dir}/library/add_custom_download_tmp/"

  done

  #########################
  ####  kraken2_build  ####
  #########################

  ## download-taxonomy
  if [[ -n "${taxonomy_db}" ]]; then
    if [[ -d "$taxonomy_db" ]]; then
      mkdir -p "${out_db_dir}"
      if ! cp -R "${taxonomy_db}/" "${out_db_dir}/taxonomy"; then  # 'cp -R' OR 'ln -s' ???
        echo "Error copy taxonomy database."
        exit 1
      fi
    else
      echo "Error 'taxonomy_db' ('$taxonomy_db') not directory."
    fi
  else
    if ! kraken2-build --db "${out_db_dir}/" --download-taxonomy ${args_dl_tax}; then
      echo "Error downloading taxonomy."
      exit 1
    fi
  fi

  ## download-library
  if [[ -n "$library" ]]; then
    for i in "${!library_array[@]}"; do
      library_i="${library_array[$i]}"
      if ! kraken2-build --db "${out_db_dir}/" --download-library "${library_i}" ${args_dl_lib}; then
        echo "Error downloading library ${library_i}"
        exit 1
      fi
    done
  fi

  ## add-to-library
  if [ -d "${out_db_dir}/library/add_custom_tmp/" ]; then
    find "${out_db_dir}/library/add_custom_tmp/" -type f \( -name "*.fa" -o -name "*.fna" -o -name "*.fasta" -o -name "*.fa.gz" -o -name "*.fna.gz" -o -name "*.fasta.gz" \) | while read -r fa_file; do
      if ! kraken2-build --db "${out_db_dir}/" --add-to-library "$fa_file" ${args_add_lib}; then
        echo "Error adding file $fa_file to library."
        exit 1
      fi
    done
    rm -rf "${out_db_dir}/library/add_custom_tmp/"
  fi
fi

if [ "$step" = "all" ] || [ "$step" = "post" ]; then
  ## build
  if ! kraken2-build --build --db "${out_db_dir}/" --threads "${threads}" ${args_build}; then
    echo "Error building Kraken2 database."
    exit 1
  fi

  ## clean
  ## what about "rm -rf ${out_db_dir}/taxonomy/ ${out_db_dir}/library/" ?
  if ! kraken2-build --clean --db "${out_db_dir}/"; then
    echo "Error cleaning Kraken2 database."
    exit 1
  fi
fi

echo -e "\n\n#[$(date)]: END\n\n"
