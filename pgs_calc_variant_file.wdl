version 1.0

import "https://raw.githubusercontent.com/UW-GAC/primed-file-checks/refs/heads/main/validate_pgs_individual.wdl" as validate
import "primed_calc_pgs.wdl" as this

workflow pgs_calc_variant_file {
    input {
        File pgen
        File pvar
        File psam
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
        Boolean overwrite = false
        Boolean import_tables = true
        Boolean check_bucket_paths = true
    }

    call this.match_scorefile {
        input:
            scorefile = scorefile,
            pvar = pvar,
            genome_build = genome_build,
            min_overlap = min_overlap,
            pgs_name = pgs_model_id,
            pgs_id = pgs_model_id,
            sampleset_name = sampleset_name
    }

    call this.plink_score {
        input:
            scorefile = match_scorefile.match_scorefile,
            pgen = pgen,
            pvar = pvar,
            psam = psam,
            prefix = sampleset_name
    }

    if (ancestry_adjust) {
        call this.adjust_prs {
            input:
                scores = plink_score.scores,
                pcs = select_first([pcs, ""])
        }
    }

    call this.prep_pgs_table {
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
               overwrite = overwrite,
               import_tables = import_tables,
               check_bucket_paths = check_bucket_paths
    }

    call chr_prefix {
        input:
            file = plink_score.variants
    }

    output {
        File match_log = match_scorefile.match_log
        File match_summary = match_scorefile.match_summary
        File score_file = plink_score.scores
        File variants = plink_score.variants
        File variants_chr_prefix = chr_prefix.outfile
        File? adjusted_score_file = adjust_prs.adjusted_scores
    }

     meta {
          author: "Stephanie Gogarten"
          email: "sdmorris@uw.edu"
     }
}


task chr_prefix {
    input {
        File file
    }

    Int disk_size = ceil(5*(size(file, "GB"))) + 10
    String filename = basename(file, ".gz")

    command <<<
        set -e -o pipefail
        awk '{$1="chr"$1; print $0}' OFS="\t" ~{file} > ~{filename}_chrprefix
    >>>

    output {
        File outfile = "~{filename}_chrprefix"
    }

    runtime {
        docker: "quay.io/biocontainers/plink2:2.00a5.12--h4ac6f70_0"
        disks: "local-disk ~{disk_size} SSD"
        memory: "16G"
    }
}
