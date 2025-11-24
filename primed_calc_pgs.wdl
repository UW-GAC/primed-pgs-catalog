version 1.0

import "https://raw.githubusercontent.com/UW-GAC/pgsc_calc_wdl/refs/heads/main/pgsc_calc_prepare_genomes.wdl" as prep
import "https://raw.githubusercontent.com/UW-GAC/primed-file-checks/refs/heads/main/validate_pgs_individual.wdl" as validate

workflow primed_calc_pgs {
    input {
        Array[File] vcf
        File scorefile
        String genome_build
        Float min_overlap
        String pgs_model_id
        String sampleset_name
        String dest_bucket
        String? primed_dataset_id
        Boolean ancestry_adjust
        File? pcs
        String model_url
        String workspace_name
        String workspace_namespace
        Boolean import_tables = true
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

    if (ancestry_adjust) {
        call adjust_prs {
            input:
                scores = plink_score.scores,
                pcs = select_first([pcs, ""])
        }
    }

    call prep_pgs_table {
        input:
            dest_bucket = dest_bucket,
            score_file = plink_score.scores,
            report_file = match_scorefile.match_summary,
            adjusted_score_file = adjust_prs.adjusted_scores,
            pgs_model_id = pgs_model_id,
            sampleset_name = sampleset_name,
            primed_dataset_id = primed_dataset_id
    }

    call validate.validate_pgs_individual {
        input: table_files = prep_pgs_table.table_files,
               model_url = model_url,
               workspace_name = workspace_name,
               workspace_namespace = workspace_namespace,
               import_tables = import_tables
    }

    output {
        File match_log = match_scorefile.match_log
        File match_summary = match_scorefile.match_summary
        File score_file = plink_score.scores
        File variants = plink_score.variants
        File? adjusted_score_file = adjust_prs.adjusted_scores
        File validation_report = validate_pgs_individual.validation_report
        Array[File]? tables = validate_pgs_individual.tables
        String? md5_check_summary = validate_pgs_individual.md5_check_summary
        File? md5_check_details = validate_pgs_individual.md5_check_details
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


task adjust_prs {
    input {
        File scores
        File pcs
        Int mem_gb = 16
    }

    Int disk_size = ceil(2.5*(size(scores, "GB") + size(pcs, "GB"))) + 10

    command <<<
        R << RSCRIPT
        library(tidyverse)
        source('https://raw.githubusercontent.com/UW-GAC/pgsc_calc_wdl/refs/heads/main/ancestry_adjustment.R')
        scores <- read_tsv('~{scores}')
        pcs <- read_tsv('~{pcs}')
        scores <- prep_scores(scores)
        model <- fit_prs(scores, pcs)
        mean_coef <- model[['mean_coef']]
        var_coef <- model[['var_coef']]
        adjusted_scores <- adjust_prs(scores, pcs, mean_coef, var_coef)
        write_tsv(adjusted_scores, 'adjusted_scores.txt')
        RSCRIPT
    >>>

    output {
        File adjusted_scores = "adjusted_scores.txt"
    }

    runtime {
        docker: "rocker/tidyverse:4"
        disks: "local-disk ~{disk_size} SSD"
        memory: "~{mem_gb}G"
    }
}


task prep_pgs_table {
    input {
        String dest_bucket
        File score_file
        File report_file
        File? adjusted_score_file
        String pgs_model_id
        String sampleset_name
        String? primed_dataset_id
        Int mem_gb = 16
    }

    Int disk_size = ceil(3*(size(score_file, "GB"))) + 10
    Boolean has_adjusted = defined(adjusted_score_file)
    Boolean has_id = defined(primed_dataset_id)

    command <<<
        R << RSCRIPT
        library(tidyverse)
        library(AnVIL)
        dat <- read_tsv("~{score_file}")
        score_file_path <- file.path("~{dest_bucket}", paste("~{sampleset_name}", "~{pgs_model_id}", basename("~{score_file}"), sep="_"))
        gsutil_cp("~{score_file}", score_file_path)
        report_file_path <- file.path("~{dest_bucket}", paste("~{sampleset_name}", "~{pgs_model_id}", basename("~{report_file}"), sep="_"))
        gsutil_cp("~{report_file}", report_file_path)
        df <- tibble(
            pgs_model_id = "~{pgs_model_id}",
            file_path = score_file_path,
            file_readme_path = report_file_path,
            md5sum = tools::md5sum("~{score_file}"),
            n_subjects = nrow(dat),
            sampleset = "~{sampleset_name}",
            ancestry_adjusted = "FALSE"
        )
        if (as.logical(toupper("~{has_adjusted}"))) {
            dat_adj <- read_tsv("~{adjusted_score_file}")
            adjusted_score_file_path <- file.path("~{dest_bucket}", paste("~{sampleset_name}", "~{pgs_model_id}", basename("~{adjusted_score_file}"), sep="_"))
            gsutil_cp("~{adjusted_score_file}", adjusted_score_file_path)
            df_adj <- tibble(
                pgs_model_id = "~{pgs_model_id}",
                file_path = adjusted_score_file_path,
                file_readme_path = report_file_path,
                md5sum = tools::md5sum("~{adjusted_score_file}"),
                n_subjects = nrow(dat_adj),
                sampleset = "~{sampleset_name}",
                ancestry_adjusted = "TRUE"
            )
            df <- bind_rows(df, df_adj)
        }
        if (as.logical(toupper("~{has_id}"))) {
            df <- df %>%
                mutate(primed_dataset_id = "~{primed_dataset_id}")
        }
        write_tsv(df, 'pgs_individual_file_table.tsv')
        RSCRIPT
    >>>

    output {
        Map[String, File] table_files = {
            "pgs_individual_file": "pgs_individual_file_table.tsv"
        }
    }

    runtime {
        docker: "uwgac/primed-pgs-catalog:0.7.0"
        disks: "local-disk ~{disk_size} SSD"
        memory: "~{mem_gb}G"
    }
}
