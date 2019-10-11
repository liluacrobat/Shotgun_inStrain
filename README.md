# Bhattlab workflows
Computational workflows for metagenomics tasks, packaged with Snakemake and singularity

### Table of contents

 1. [Setup](manual/setup.md)
 2. [Running a workflow](manual/running.md)
 3. Available workflows
    - [**Preprocessing** metagenomic data](manual/preprocessing.md)
    - [Metagenomic **Assembly**](manual/assembly.md)
    - [Metagenomic **Binning**](manual/binning.md)
    - [Metagenomic classification with **Kraken2**](https://github.com/bhattlab/kraken2_classification)
    - [**Sourmash** read comparison](manual/sourmash.md)
    - [**Download SRA** data](manual/download_sra.md)
    - [Comparative microbial genomics pipelines](manual/comparative_genomics.md)
	  

### Quickstart




# Assembly

Assemble preprocessed read data, using Megahit, Spades or both. Evaluates result with Quast. Accepts a tab-delimited input table, specified in the config.yaml (see example below). Comment lines are specified with the # character. An input table is automatically generated at the end of the preprocessing pipeline and can be found at `01_processing/assembly_input.txt`.

```
#Sample Reads1.fq[.gz][,Reads2.fq[.gz][,orphans.fq[.gz]]]
sample_a    a_1.fq,a_2.fq,a_orphans.fq
sample_b    b_1.fq,b_2.fq,b_orphans.fq
```

# Sourmash
Workflow for kmer-based comparison of sequencing reads. For the details on what sourmash and MinHash are, see the [sourmash docs](https://sourmash.readthedocs.io/en/latest/). Install and activate the `sourmash.yaml` conda environment in the `envs` folder.

There are two inputs required in the config file: the final output directory of the preprocessing pipeline (something like `preprocessing/01_processing/05_sync`) and the output directory. By default, kmer comparisons are calculated at k=21, k=31 and k=51. Output files include:
- Matrices of pairwise jaccard distances between all samples (`04_sourmash_compare/compare_k21.csv`)
- Clustered heatmaps of pairwise distances (`04_sourmash_compare/compare_k21_heatmap_ward.D2.pdf`)

Steps of the workflow include:
- Concatenate all reads into a single file
- Trim lowly abundant kmers
- Build MinHash sketches for each file
- Compare each pair of signatures to get pairwise Jaccard distances
- Downstream processing and plotting

# Metagenomic binning
Binning is essentially clustering for assembled contigs. Create draft metagenome-assembled genomes and evaluate their completeness, contamination and other metrics with these helpful tools!

There are two binning workflows in the `binning` folder. `bin_metabat.snakefile` uses a single binning method ([metabat2](https://peerj.com/articles/1165/)), while `bin_das_tool.snakefile` uses several tools and integrates the result with [DASTool](https://www.nature.com/articles/s41564-018-0171-1). Both use the same downstream evaluation and reporting tools. The DASTool pipeline was made by [Alyssa Benjamin](https://github.com/ambenj).

In contrast to other workflows, you must run binning individually for each sample. Change the following options in the `binning/config_binning.yaml` file to match your project:
- assembly
- sample
- outdir_base
- reads1
- reads2
- read_length

You can launch either workflow using singularity to manage all dependencies with a command like, submitting jobs to the SCG cluster:
```
snakemake --configfile path/to/config_binning.yaml --snakefile path/to/bin_metabat.snakefile \
--profile scg --jobs 100 --use-singularity --singularity-args '--bind /labs/ --bind /scratch/ '
```

## Running binning on many samples
To make this workflow easy to run on many samples, you need to make a configuration file for each one. If all were preprocessed and assembled with our workflows in the same directory, first make one config file to match your samples. Call this `config_example.yaml`. Put your list of samples, one per line, in `sample_list.txt`. Then you can replace the sample name in the configfile in a loop, changing SAMPLE to the name you used with the example configfile:
```
mkdir configfiles
while read line; do
    echo "$line"
    sed "s/SAMPLE/$line/g" config_example.yaml > configfiles/config_"$line".yaml
done < todo_binning.txt 
```

Then, you can run the snakemake workflow for each configfile. Either do this in separate windows in tmux, or run it as a loop. This loop is sequential, but you could even get fancy and run something in parallel with xargs... Change the paths here to correspond to where you have the snakefile and configfiles. 
```
for c in configfiles/*.yaml; do
    echo "starting $c"
    snakemake --snakefile ~/projects/bhattlab_workflows/binning/bin_das_tool.snakefile --configfile "$c" --use-singularity --singularity-args '--bind /labs/ --bind /scratch/' --profile scg --jobs 99 --rerun-incomplete
done
```

# Dumping reads from SRA 
Given a SRR ID number, this will download reads from SRA, using many threads in parallel to speed up the process. Specify the SRR ID number on the command line (replacing SRRXXXXX) . Reads are downloaded into a new folder in your current working directory. 
```
snakemake --snakefile /path/to/sra_download/sra_download.snakefile \
--config srr=SRRXXXXX \
--use-singularity --profile scg --jobs 1
```

# Classification and taxonomic barplots
Deprecated. See our [Kraken2](https://github.com/bhattlab/kraken2_classification) github for the most up to date classification workflow.
<!--stackedit_data:
eyJoaXN0b3J5IjpbNjYzNTk4Nzg3XX0=
-->