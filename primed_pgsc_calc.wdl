version 1.0

import "https://raw.githubusercontent.com/UW-GAC/pgsc_calc_wdl/refs/heads/data_model/pgsc_calc.wdl" as pgsc_calc
import "https://raw.githubusercontent.com/UW-GAC/primed-file-checks/refs/heads/pgs/validate_pgs_individual.wdl" as validate

workflow primed_pgsc_calc {
    input {
        File scorefile
        String pgs_model_id
        String model_url
        String workspace_name
        String workspace_namespace
    }

    call pgsc_calc.pgsc_calc {
        input:
            scorefile = scorefile
    }

    call prep_pgs_table {
        input:
            score_files = pgsc_calc.score_files,
            pgs_model_id = pgs_model_id
    }

    call validate.validate_pgs_individual {
        input: table_files = prep_pgs_table.table_files,
               model_url = model_url,
               workspace_name = workspace_name,
               workspace_namespace = workspace_namespace
    }

    output {
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
        Array[File] score_files
        String pgs_model_id
        Int mem_gb = 16
    }

    Int disk_size = ceil(1.5*(size(score_files, "GB"))) + 10

    command <<<
        R << RSCRIPT
        library(tidyverse)
        files <- readLines('~{write_lines(score_files)}')
        scorefile <- files[grepl("scores", files)]
        report <- files[grepl("report", files)]
        dat <- read_tsv(scorefile)
        nsubj <- nrow(dat)
        df <- tibble(
            pgs_model_id = "~{pgs_model_id}",
            file_path = scorefile,
            file_readme_path = report,
            md5sum = tools::md5(scorefile),
            n_subjects = nsubj
        )
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