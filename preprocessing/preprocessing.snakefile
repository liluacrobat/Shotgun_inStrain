import re,os

################################################################################
# specify project directories
DATA_DIR    = config["raw_reads_directory"]
PROJECT_DIR = config["output_directory"]
READ_SUFFIX = config["read_specification"]
EXTENSION   = config["extension"]

# get file names
FILES = [f for f in os.listdir(DATA_DIR) if f.endswith(tuple(['fastq.gz', 'fq.gz']))]
SAMPLE_PREFIX = list(set([re.split('_1.|_2.|_R1|_R2', i)[0] for i in FILES]))

################################################################################
localrules: assembly_meta_file

rule all:
	input:
		expand(os.path.join(PROJECT_DIR,"01_processing/04_host_align/{sample}_rmHost_orphan.fq"), sample=SAMPLE_PREFIX),
		expand(os.path.join(PROJECT_DIR,  "qc/00_qc_reports/pre_fastqc/{sample}_{read}_fastqc.html"), sample=SAMPLE_PREFIX, read=READ_SUFFIX),
		expand(os.path.join(PROJECT_DIR,  "01_processing/00_qc_reports/post_fastqc/{sample}_{read}_fastqc.html"), sample=SAMPLE_PREFIX, read=READ_SUFFIX),
		# os.path.join(PROJECT_DIR, "01_processing/assembly_input.txt")


################################################################################
rule pre_fastqc:
	input:  os.path.join(DATA_DIR, "{sample}_{read}") + EXTENSION
	output: os.path.join(PROJECT_DIR,  "qc/00_qc_reports/pre_fastqc/{sample}_{read}_fastqc.html")
	threads: 1
	resources:
        	time = 1,
        	mem = 16
	shell: """
	   mkdir -p {PROJECT_DIR}/01_processing/00_qc_reports/pre_fastqc/
	   fastqc {input} --outdir {PROJECT_DIR}/01_processing/00_qc_reports/pre_fastqc/
	"""

################################################################################
rule trim_galore:
	input:
		fwd = os.path.join(DATA_DIR, "{sample}_") + READ_SUFFIX[0] + EXTENSION,
	 	rev = os.path.join(DATA_DIR, "{sample}_") + READ_SUFFIX[1] + EXTENSION
	output:
		fwd = os.path.join(PROJECT_DIR, "01_processing/01_trimmed/{sample}_") +  READ_SUFFIX[0] + "_val_1.fq.gz",
		rev = os.path.join(PROJECT_DIR, "01_processing/01_trimmed/{sample}_") +  READ_SUFFIX[1] + "_val_2.fq.gz",
		orp = os.path.join(PROJECT_DIR, "01_processing/01_trimmed/{sample}_unpaired.fq.gz")
	threads: 4
	resources:
		mem=32,
		time=3
	params:
		q_min   = config['trim_galore']['quality'],
		left    = config['trim_galore']['start_trim'],
		min_len = config['trim_galore']['min_read_length']
	shell: """
		mkdir -p {PROJECT_DIR}/01_processing/01_trimmed/
		trim_galore --quality {params.q_min} \
			--clip_R1 {params.left} --clip_R2 {params.left} \
			--length {params.min_len} \
			--output_dir {PROJECT_DIR}/01_processing/01_trimmed/ \
			--paired {input.fwd} {input.rev} \
			--retain_unpaired
		# merge unpaired reads - delete intermediate files
		zcat {PROJECT_DIR}/01_processing/01_trimmed/{wildcards.sample}_1_unpaired_1.fq.gz {PROJECT_DIR}/01_processing/01_trimmed/{wildcards.sample}_2_unpaired_2.fq.gz | gzip >> {PROJECT_DIR}/01_processing/01_trimmed/{wildcards.sample}_unpaired.fq.gz
		rm {PROJECT_DIR}/01_processing/01_trimmed/{wildcards.sample}_1_unpaired_1.fq.gz {PROJECT_DIR}/01_processing/01_trimmed/{wildcards.sample}_2_unpaired_2.fq.gz
	"""

################################################################################
rule dereplicate:
	input:
		fwd = rules.trim_galore.output.fwd,
		rev = rules.trim_galore.output.rev,
		orp = rules.trim_galore.output.orp
	output:
		fwd = os.path.join(PROJECT_DIR, "01_processing/02_dereplicate/{sample}_nodup_PE1.fastq"),
		rev = os.path.join(PROJECT_DIR, "01_processing/02_dereplicate/{sample}_nodup_PE2.fastq"),
		orp = os.path.join(PROJECT_DIR, "01_processing/02_dereplicate/{sample}_nodup_unpaired.fastq")
	threads: 4
	resources:
		mem=32,
		time=24
	shell: """
		mkdir -p {PROJECT_DIR}/01_processing/02_dereplicate/
		seqkit rmdup --by-seq {input.fwd} > {output.fwd} \
			-D {PROJECT_DIR}/01_processing/02_dereplicate/{wildcards.sample}_1_details.txt
		seqkit rmdup --by-seq {input.rev} > {output.rev} \
			-D {PROJECT_DIR}/01_processing/02_dereplicate/{wildcards.sample}_2_details.txt
		seqkit rmdup --by-seq {input.orp} > {output.orp} \
			-D {PROJECT_DIR}/01_processing/02_dereplicate/{wildcards.sample}_unpaired_details.txt
	"""

################################################################################
rule sync:
	input:
		rep_fwd   = rules.trim_galore.output.fwd,
		derep_fwd = rules.dereplicate.output.fwd,
		derep_rev = rules.dereplicate.output.rev
	output:
		fwd = os.path.join(PROJECT_DIR, "01_processing/03_sync/{sample}_1.fastq"),
		rev = os.path.join(PROJECT_DIR, "01_processing/03_sync/{sample}_2.fastq"),
		orp = os.path.join(PROJECT_DIR, "01_processing/03_sync/{sample}_orphans.fastq")
	shell: """
		mkdir -p {PROJECT_DIR}/01_processing/03_sync/
		/labs/asbhatt/ribado/tools/bhattlab_workflows/preprocessing/scripts/sync.py {input.rep_fwd} {input.derep_fwd} {input.derep_rev} {output.fwd} {output.rev} {output.orp}
	"""

################################################################################
rule post_fastqc:
	input:  rules.sync.output
	output: os.path.join(PROJECT_DIR,  "01_processing/00_qc_reports/post_fastqc/{sample}_{read}_fastqc.html")
	threads: 1
	resources:
        	time = 1,
        	mem = 16
	shell: """
	   mkdir -p {PROJECT_DIR}/01_processing/00_qc_reports/post_fastqc/
	   fastqc {input} -f fastq --outdir {PROJECT_DIR}/01_processing/00_qc_reports/post_fastqc/
	 """

################################################################################
rule rm_host_reads:
	input:
	 	bwa_index = config['rm_host_reads']['host_genome'],
		fwd       = rules.sync.output.fwd,
		rev       = rules.sync.output.rev,
		orp       = rules.sync.output.orp
	output:
		unmapped_1 = os.path.join(PROJECT_DIR, "01_processing/04_host_align/{sample}_rmHost_1.fq"),
		unmapped_2 = os.path.join(PROJECT_DIR,"01_processing/04_host_align/{sample}_rmHost_2.fq"),
		unmapped_orp = os.path.join(PROJECT_DIR,"01_processing/04_host_align/{sample}_rmHost_orphan.fq")
	threads: 4
	resources:
		mem=16,
		time=24
	shell: """
		mkdir -p {PROJECT_DIR}/01_processing/04_host_align/
		# if an index needs to be built, use bwa index ref.fa
		# run first on the paired reads
		bwa mem -t {threads} {input.bwa_index} {input.fwd} {input.rev} | samtools view -bS - | samtools bam2fq -f 4 -1 {output.unmapped_1} -2 {output.unmapped_2} - ;
		# run on the orphan reads
		bwa mem -t {threads} {input.bwa_index} {input.orp} | samtools view -bS - | samtools bam2fq -f 4 - > {output.unmapped_orp}
	"""

################################################################################
rule assembly_meta_file:
	input:  rules.rm_host_reads.output.unmapped_1
	output: os.path.join(PROJECT_DIR, "01_processing/assembly_input.txt")
	shell: """
		prefix=$(echo {input} | cut -d'_' -f1)
		files=$(find $(echo {input} | cut -d'_' -f1)* -maxdepth 0 -type f | tr '\n' ',' | sed 's/\(.*\),/\1 /' )
 		echo "$prefix	$files" >> {output}
	"""
