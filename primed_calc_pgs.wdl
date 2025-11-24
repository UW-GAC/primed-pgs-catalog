version 1.0

import "https://raw.githubusercontent.com/UW-GAC/pgsc_calc_wdl/refs/heads/main/pgsc_calc_prepare_genomes.wdl" as prep

workflow primed_calc_pgs {
    input {
        Array[File] vcf
        File scorefile
        String genome_build
        Float min_overlap
        String pgs_model_id
        String sampleset_name
    }

    call prep.pgsc_calc_prepare_genomes {
        input:
            vcf = vcf,
            merge_chroms = true
    }

    call match_scorefile {
        input:
            scorefile = scorefile,
            pvar = pgsc_calc_prepare_genomes.pvar[0],
            genome_build = genome_build,
            min_overlap = min_overlap,
            pgs_name = pgs_model_id,
            pgs_id = pgs_model_id,
            sampleset_name = sampleset_name
    }

    call plink_score {
        input:
            scorefile = match_scorefile.match_scorefile,
            pgen = pgsc_calc_prepare_genomes.pgen[0],
            pvar = pgsc_calc_prepare_genomes.pvar[0],
            psam = pgsc_calc_prepare_genomes.psam[0],
            prefix = sampleset_name
    }

    output {
        File scores = plink_score.scores
        File variants = plink_score.variants
        File match_log = match_scorefile.match_log
        File match_summary = match_scorefile.match_summary
    }

     meta {
          author: "Stephanie Gogarten"
          email: "sdmorris@uw.edu"
     }
}


task match_scorefile {
    input {
        File scorefile
        File pvar
        String genome_build
        Float min_overlap
        String pgs_name = "unknown"
        String pgs_id = "unknown"
        String trait_reported = "unknown"
        String sampleset_name = "cohort"
        Int mem_gb = 128
        Int cpu = 2
    }

    Int disk_size = ceil(3*(size(scorefile, "GB") + size(pvar, "GB"))) + 10

    command <<<
        set -e -o pipefail

        # add header to scoring file
        R << RSCRIPT
        library(readr)
        library(dplyr)
        scorefile <- read_tsv("~{scorefile}")
        outfile <- "scorefile.txt"
        header <- c(
            "#pgs_name=~{pgs_name}",
            "#pgs_id=~{pgs_id}",
            "#trait_reported=~{trait_reported}",
            "#genome_build=~{genome_build}"
        )
        writeLines(header, outfile)
        dat <- read_tsv("~{scorefile}", comment = "#") %>%
            select(chr_name, chr_position, effect_allele, other_allele, effect_weight)
        write_tsv(dat, outfile, append=TRUE, col_names=TRUE)
        RSCRIPT

        # format pvar to drop header and extra columns
        sed -n '/^##/!p' ~{pvar} | awk -v OFS='\t' '{print $1, $2, $3, $4, $5}'  > formatted.pvar

        # format scoring file for use with pgscatalog-match
        pgscatalog-combine -s scorefile.txt -t ~{genome_build} -o formatted.txt

        mkdir output
        pgscatalog-match --dataset ~{sampleset_name} --scorefiles formatted.txt --target formatted.pvar --outdir output --min_overlap ~{min_overlap}
    >>>

    output {
        File match_scorefile = "output/~{sampleset_name}_ALL_additive_0.scorefile.gz"
        File match_log = "output/~{sampleset_name}_log.csv.gz"
        File match_summary = "output/~{sampleset_name}_summary.csv"
    }

    runtime {
        docker: "uwgac/primed-pgs-queries:0.4.1"
        disks: "local-disk ~{disk_size} SSD"
        memory: "~{mem_gb}G"
    }
}


task plink_score {
    input {
        File scorefile
        File pgen
        File pvar
        File psam
        String prefix = "out"
        Int mem_gb = 16
        Int cpu = 2
    }
    
    Int disk_size = ceil(1.5*(size(pgen, "GB") + size(pvar, "GB") + size(psam, "GB") + size(scorefile, "GB"))) + 10

    command <<<
        plink2 --pgen ~{pgen} --pvar ~{pvar} --psam ~{psam} --score ~{scorefile} \
            no-mean-imputation header-read list-variants cols=+scoresums \
            --out ~{prefix}
    >>>

    output {
        File scores = "~{prefix}.sscore"
        File variants = "~{prefix}.sscore.vars"
    }

    runtime {
        docker: "quay.io/biocontainers/plink2:2.00a5.12--h4ac6f70_0"
        disks: "local-disk ~{disk_size} SSD"
        memory: "~{mem_gb}G"
        cpu: "~{cpu}"
    }
}
