version 1.0

import "https://raw.githubusercontent.com/UW-GAC/pgsc_calc_wdl/refs/heads/data_model/pgsc_calc.wdl" as pgsc_calc
import "https://raw.githubusercontent.com/UW-GAC/primed-file-checks/refs/heads/pgs/validate_pgs_individual.wdl" as validate

workflow primed_pgsc_calc {
    input {
        File scorefile
        String pgs_model_id
        String sampleset_name
        String? primed_dataset_id
        Boolean ancestry_adjust
        File? pcs
        String model_url
        String workspace_name
        String workspace_namespace
        Boolean import_tables = true
    }

    call pgsc_calc.pgsc_calc {
        input:
            scorefile = scorefile,
            sampleset_name = sampleset_name
    }

    if (ancestry_adjust) {
        call adjust_prs {
            input:
                scores = pgsc_calc.score_file,
                pcs = select_first([pcs, ""])
        }
    }

    call prep_pgs_table {
        input:
            score_file = pgsc_calc.score_file,
            score_file_path = pgsc_calc.score_file,
            report_file_path = pgsc_calc.report_file,
            adjusted_score_file = adjust_prs.adjusted_scores,
            adjusted_score_file_path = adjust_prs.adjusted_scores,
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
        File score_file = pgsc_calc.score_file
        File report_file = pgsc_calc.report_file
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


task prep_pgs_table {
    input {
        File score_file
        String score_file_path
        String report_file_path
        File? adjusted_score_file
        String? adjusted_score_file_path
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
        dat <- read_tsv("~{score_file}")
        df <- tibble(
            pgs_model_id = "~{pgs_model_id}",
            file_path = "~{score_file_path}",
            file_readme_path = "~{report_file_path}",
            md5sum = tools::md5sum("~{score_file}"),
            n_subjects = nrow(dat),
            sampleset = "~{sampleset_name}",
            ancestry_adjusted = "FALSE"
        )
        if (as.logical(toupper("~{has_adjusted}"))) {
            dat_adj <- read_tsv("~{adjusted_score_file}")
            df_adj <- tibble(
                pgs_model_id = "~{pgs_model_id}",
                file_path = "~{adjusted_score_file_path}",
                file_readme_path = "~{report_file_path}",
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
        docker: "rocker/tidyverse:4"
        disks: "local-disk ~{disk_size} SSD"
        memory: "~{mem_gb}G"
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
        scores <- select(scores, IID, SUM) %>%
            mutate(IID = as.character(IID))
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
