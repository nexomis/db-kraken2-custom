# db-kraken2-custom

## Container
from docker img: `quay.io/biocontainers/kraken2:2.1.3--pl5321hdcf5f25_1` (!! too big img 333MB !!)

*ToDo: Create a new one dedicated to "simple" index building from 'quay.io/nexomis/kraken2:2.1.3' and including important missing tools (rsync, tools for remove low complexity, ... but no need to include all recquired tools (ex: peptide sequence inclusion tools))*

### CURRENT STATUS : ~~under_dev~~ | under_test | ~~in_prod~~
*(not all features and feature combinations have yet been fully tested)*

## Description
### Taxonomy
Arguments: `-x`  
If you have already downloaded the kraken2 taxonomy database, you can set its path with this argument. This will lead to a (complete*) copy of the database in `<out_db_dir>` and avoid downloading (`--download-taxonomy`).  
For information, the complete database after `--download-taxonomy` (downloaded, decompressed and processed) currently weighs 40G.0
**probably improved by copying only the information relative to interest taxon/accesion_id or by using a symbolic link instead of complete copy(`ln -s` instead of `cp -R`)*.

### Nucleotide Sequences
Nucleotide sequence incorporation into the newly created database can be achieved in 3 ways, which can be used alone or in combination:
#### option 1:
Arguments: `i` and `-n`  
Import genomic and transcriptomic sequences from 'ftp.ncbi.nlm.nih.gov/genomes/all/':
 - *_genomic.fna.gz: top-level (exhaustive without unless redundancy) but repeatitive sequences are soft masked (if need to unmask, download manually and perform `awk '{if(/^[^>]/)$0=toupper($0);print $0}' genomic.fna > genomic.unmasked.fna` and submit to this script via **option 3**).
 - *_rna_from_genomic.fna.gz: no need to concatenate with *_rna.fna.gz as it must be included in rna_from_genomic.fna.gz (?). In addition '*_rna.fna.gz' seems to be specific to refSeq ftp (not in genbank ftp))

#### option 2:
Argument: `-l`  
Kraken2 import of predefined `library`. Current available option: `'archaea', 'bacteria', 'plasmid', 'viral', 'human', 'fungi', 'plant', 'protozoa', 'nr', 'nt', 'UniVec', 'UniVec_Core'`.  
Note: Only the genome seems to be incorporated (at least this is the case for 'human').

#### option 3:
No specific arguments, but the `-f` option must be used (with the risk of data loss !!).  
The fasta to be integrated must be placed in the temporary folder `<out_db_dir>/library/add_custom_tmp/`.  
They must be in the right format, especially for the ability to attribute them taxonomically by means of a valid accession id (NCBI) or the addition of a taxon id in the name of each sequence. See kraken2 manual:
```
Sequences not downloaded from NCBI may need their taxonomy information assigned explicitly. This can be done using the string kraken:taxid|XXX in the sequence ID, with XXX replaced by the desired taxon ID. For example, to put a known adapter sequence in taxon 32630 ("synthetic construct"), you could use the following:

>sequence16|kraken:taxid|32630  Adapter sequence
CAAGCAGAAGACGGCATACGAGATCTTCGAGTGACTGGAGTTCCTTGGCACCCGAGAATTCCA
```

## Exemple usage:
### Only Human:
**option 1** (genome + transcriptome): 
`./build_custom_db.sh -i GCF_000001405.40 -n GRCh38.p14 -o kraken2DB_GRCh38 -t 8`

**option 2** (genome):
`./build_custom_db.sh -l human -o kraken2DB_human -t 8`

### Human + bacteria and plasmid kraken library:
**option 1 (human) + option 2 (bacteria and plasmid)**
`./build_custom_db.sh -i GCF_000001405.40 -n GRCh38.p14 -o kraken2DB_GRCh38_bacteria -t 8 -l bacteria,plasmid`

**option 2** (genome):
`./build_custom_db.sh -l human,bacteria,plasmid -o kraken2DB_human_bacteria -t 8`

## Potential interest kraken2-build option :
Managable by argument in section `Kraken2-Build Arguments`
 - `--download-library`/`--download-taxonomy`: maybe is better with `--use-ftp` (instead of rsync) 
 - `--add-to-library`: `--no-masking` (e.g: for classic virus this simplify dowstream assembly whithout risk to exclude viral reads at kraken host exclussion step and probably accelerade this step of `kraken2-index`).
 - `--build`: `--fast-build` and `--skip-maps`


## Potential improvement:
 - create specific docker img ?
 - improve taxonomy directorie copy : symbolic ling OR extraction of only interest features
 - automatise option3:
   - cp input fasta path on good directories
   - add correspond taxid to all sequence name