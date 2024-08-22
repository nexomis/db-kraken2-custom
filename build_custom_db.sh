#!/usr/bin/bash

set -e

################
####  help  ####
################

function show_help() {
  cat << EOF
Usage: $0 [options]

Script to download genomic and transcriptomic sequences and build a Kraken2 database.

Input/Output Arguments:
Reminder: at least one of the parameters between gnom_acc_id/gnom_acc_name and library must be non-null and valid, otherwise there is no reference on which to create the database and therefore no database can be created.

  -i, (gnom_acc_id)    : NCBI RefSeq or Genbank accession ID(s), separated by commas if multiple. E.g., "GCF_000001405.40"
  -n, (gnom_acc_name)  : Corresponding name(s) for the accession IDs, separated by commas if multiple. E.g., "GRCh38.p14"
  -l, (library)        : Kraken2 library IDs, separated by commas if multiple.
                         Valid values are: 'archaea', 'bacteria', 'plasmid', 'viral', 'human', 'fungi', 'plant', 'protozoa', 'nr', 'nt', 'UniVec', 'UniVec_Core'.
  -o, (out_db_dir)     : [recquired] - Directory where the Kraken2 database will be created.
                         Should not exist unless 'force' is set to true.
  -f, (force)          : If set up, allows the script to proceed even if 'out_db_dir' already exists.
                         Be careful if 'out_db_dir' already exists and is not empty, because certain file types with the right path pattern
                        (e.g. custom fasta) will be included in the resulting database (this can be useful to resume incomplete excecution).
                        In addition, the contents of this directory can be overwritten or deleted. Default is false.
  -x, (taxonomy_db)    : Directory of an existing Kraken2 taxonomy database to link to the new database.
                         If specified '--download-taxonomy' step (from 'kraken2-build') is skipped.

Kraken2-Build Arguments:
to be incorporated as is into the command line concerned (to be provided between quotation)

  -a, (args_dl_tax)    : Additional arguments for the '--download-taxonomy' command.
  -b, (args_dl_lib)    : Additional arguments for the '--download-library' command.
  -c, (args_add_lib)   : Additional arguments for the '--add-to-library' command.
  -d, (args_build)     : Additional arguments for the '--build' command.

Other:

  -t, (threads)        : Number of threads to use for Kraken2 build. Default is 6.
  -h, (help)           : Display this help message and exit.


Examples:
  $0 -i "GCF_000001405.40" -n "GRCh38.p14" -o "kraken2DB_GRCh38" -t 8 -l "bacteria,plasmid" -a "--use-ftp"
    or
  $0 -o "kraken2DB_human" -t 8 -l "human"
EOF
  exit 1
}

######################
####  parse args  ####
######################

# Initialize variables
force=false
threads=6

# Parse command-line options
while getopts ":i:n:o:f:l:t:a:b:c:d:x:h" opt; do
  case $opt in
    i) gnom_acc_id="$OPTARG" ;;
    n) gnom_acc_name="$OPTARG" ;;
    o) out_db_dir="$OPTARG" ;;
    f) force=true ;;
    l) library="$OPTARG" ;;
    t) threads="$OPTARG" ;;
    a) args_dl_tax="$OPTARG" ;;
    b) args_dl_lib="$OPTARG" ;;
    c) args_add_lib="$OPTARG" ;;
    d) args_build="$OPTARG" ;;
    x) taxonomy_db="$OPTARG" ;;
    h) show_help ;;
    \?) echo "Invalid option: -$OPTARG" >&2; show_help ;;
    :) echo "Option -$OPTARG requires an argument." >&2; show_help ;;
  esac
done

#########################
####  validate args  ####
#########################

# recquired parameters
if ( ( [[ -z ${gnom_acc_id} ]] || [[ -z ${gnom_acc_name} ]] ) && [[ -z ${library} ]] ) || [[ -z ${out_db_dir} ]]; then
  echo "Error: If 'gnom_acc_id' and 'gnom_acc_name' are not specified, 'library' must be provided."
  show_help
fi

# Ensure out_db_dir does not exist unless force is true
if [[ -d ${out_db_dir} ]] && [[ ${force} != true ]]; then
  echo "Error: Output directory '${out_db_dir}' already exists. Use '--force' to override."
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

## Validate array lengths
if [[ ${#gnom_acc_id_array[@]} -ne ${#gnom_acc_name_array[@]} ]]; then
  echo "Error: 'gnom_acc_id' and 'gnom_acc_name' must have the same number of elements."
  exit 1
fi

########################
####  import fasta  ####
########################
## download genomic and transcriptomic sequences:
##   - *_genomic.fna.gz: top-level (exhaustive without unless redundancy) but repeatitive sequences are soft masked (if need to unmask: `awk '{if(/^[^>]/)$0=toupper($0);print $0}' genomic.fna > genomic.unmasked.fna`).
##   - *_rna_from_genomic.fna.gz: no need to concatenate with *_rna.fna.gz as it must be included in rna_from_genomic.fna.gz ? (in addition '*_rna.fna.gz' seems to be specific to refSeq ftp (not in genbank ftp))

## Download and process sequences
mkdir -p "${out_db_dir}/library/add_custom_tmp/"
for i in "${!gnom_acc_id_array[@]}"; do
  mkdir -p "${out_db_dir}/library/add_custom_download_tmp/"
  gnom_acc_id_i="${gnom_acc_id_array[$i]}"
  gnom_acc_name_i="${gnom_acc_name_array[$i]}"

  base_url="https://ftp.ncbi.nlm.nih.gov/genomes/all/${gnom_acc_id_i:0:3}/${gnom_acc_id_i:4:3}/${gnom_acc_id_i:7:3}/${gnom_acc_id_i:10:3}/${gnom_acc_id_i}_${gnom_acc_name_i}"
  if ! wget -O "${out_db_dir}/library/add_custom_download_tmp/genome_${gnom_acc_name_i}.fna.gz" \
    "${base_url}/${gnom_acc_id_i}_${gnom_acc_name_i}_genomic.fna.gz"; then
    echo "Error downloading genome ${gnom_acc_name_i}.fna.gz"
    exit 1
  fi
  if ! wget -O "${out_db_dir}/library/add_custom_download_tmp/rna_${gnom_acc_name_i}.fna.gz" \
    "${base_url}/${gnom_acc_id_i}_${gnom_acc_name_i}_rna_from_genomic.fna.gz"; then
    echo "Error downloading rna ${gnom_acc_name_i}.fna.gz"
    exit 1
  fi

  if ! zcat "${out_db_dir}/library/add_custom_download_tmp/genome_${gnom_acc_name_i}.fna.gz" \
    "${out_db_dir}/library/add_custom_download_tmp/rna_${gnom_acc_name_i}.fna.gz" \
    > "${out_db_dir}/library/add_custom_tmp/${gnom_acc_name_i}.fa"; then
    echo "Error concatenating files for ${gnom_acc_name_i}"
    exit 1
  fi

  rm -rf "${out_db_dir}/library/add_custom_download_tmp/"

done

#########################
####  kraken2_build  ####
#########################
## potential interest kraken2-build option :
##   --download-library/--download-taxonomy: maybe is better with "--use-ftp" (instead of rsync) 
##   --add-to-library: maybe is better if default process is '--no-masking' (e.g: for classic virus this simplify dowstream assembly whithout risk to exclude viral reads at kraken host exclussion step and probably accelerade krakn index building).
##   --build: maybe is better if default process is : '--fast-build' & '--skip-maps'
##   --clean: what about "rm -rf ${out_db_dir}/taxonomy/ ${out_db_dir}/library/" ?

if [[ -n "${taxonomy_db}" ]]; then
  if [[ -d "$taxonomy_db" ]]; then
    mkdir -p "${out_db_dir}"
    if ! cp -R "${taxonomy_db}/" "${out_db_dir}/taxonomy"; then  # 'cp -R' OR 'ln -s' ???
      echo "Error copy taxonomy database."
      exit 1
    fi
  else
    echo "Error 'taxonomy_db' ('$taxonomy_db') not directery."
  fi
else
  if ! kraken2-build --db "${out_db_dir}/" --threads "${threads}" --download-taxonomy ${args_dl_tax}; then
    echo "Error downloading taxonomy."
    exit 1
  fi
fi

if [[ -n "$library" ]]; then
  for i in "${!library_array[@]}"; do
    library_i="${library_array[$i]}"
    if ! kraken2-build --db "${out_db_dir}/" --threads "${threads}" --download-library "${library_i}" ${args_dl_lib}; then
      echo "Error downloading library ${library_i}"
      exit 1
    fi
  done
fi

if [ -d "${out_db_dir}/library/add_custom_tmp/" ]; then
  find "${out_db_dir}/library/add_custom_tmp/" -type f \( -name "*.fa" -o -name "*.fna" -o -name "*.fasta" -o -name "*.fa.gz" -o -name "*.fna.gz" -o -name "*.fasta.gz" \) | while read -r fa_file; do
    if ! kraken2-build --db "${out_db_dir}/" --add-to-library "$fa_file" ${args_add_lib}; then
      echo "Error adding file $fa_file to library."
      exit 1
    fi
  done
  rm -rf "${out_db_dir}/library/add_custom_tmp/"
fi

if ! kraken2-build --build --db "${out_db_dir}/" --threads "${threads}" ${args_build}; then
  echo "Error building Kraken2 database."
  exit 1
fi

if ! kraken2-build --clean --db "${out_db_dir}/"; then
  echo "Error cleaning Kraken2 database."
  exit 1
fi