version 1.0

import "https://raw.githubusercontent.com/UW-GAC/primed-file-checks/pgs/validate_pgs_model.wdl" as validate

workflow primed_fetch_pgs_catalog {
    input {
        Array[String] pgs_id
        String dest_bucket
        String model_url
        String workspace_name
        String workspace_namespace
        Boolean overwrite = false
        Boolean import_tables = false
        Boolean check_bucket_paths = true
    }

    scatter (pgs in pgs_id) {
        call fetch_pgs {
            input:
            pgs_id = pgs,
            dest_bucket = dest_bucket
        }

        call validate.validate_pgs_model {
            input:
            table_files = fetch_pgs.table_files,
            model_url = model_url,
            workspace_name = workspace_name,
            workspace_namespace = workspace_namespace,
            overwrite = overwrite,
            import_tables = import_tables,
            check_bucket_paths = check_bucket_paths
        }
    }

    output {
        Array[File] validation_report = validate_pgs_model.validation_report
        Array[Array[File]?] tables = validate_pgs_model.tables
        Array[String?] md5_check_summary = validate_pgs_model.md5_check_summary
        Array[File?] md5_check_details = validate_pgs_model.md5_check_details
        Array[String?] data_report_summary = validate_pgs_model.data_report_summary
        Array[File?] data_report_details = validate_pgs_model.data_report_details
    }
}


task fetch_pgs {
    input {
        String pgs_id
        String dest_bucket
        Boolean harmonized = true
        String assembly = "GRCh38"
        Int disk_size = 16
        Int mem_gb = 16
    }

    command <<<
        R << RSCRIPT
            source('/usr/local/primed-pgs-catalog/pgs_catalog_functions.R')
            file_table <- pgs_file_table('~{pgs_id}', dest_bucket='~{dest_bucket}', harmonized=toupper('~{harmonized}'), assembly='~{assembly}')
            analysis_tables <- pgs_analysis_tables('~{pgs_id}', assembly='~{assembly}')
            write_tsv(file_table, 'pgs_file_table.tsv')
            write_tsv(analysis_tables[['pgs_analysis']], 'pgs_analysis_table.tsv')
            write_tsv(analysis_tables[['pgs_sample_devel']], 'pgs_sample_devel_table.tsv')
        RSCRIPT
    >>>

    output {
        Map[String, File] table_files = {
            "pgs_analysis": "pgs_analysis_table.tsv",
            "pgs_sample_devel": "pgs_sample_devel_table.tsv",
            "pgs_file": "pgs_file_table.tsv"
        }
    }

    runtime {
        docker: "uwgac/primed-pgs-catalog:0.7.0"
        disks: "local-disk ~{disk_size} SSD"
        memory: "~{mem_gb}G"
    }
}
