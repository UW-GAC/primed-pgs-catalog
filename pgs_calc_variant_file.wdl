version 1.0

import "https://raw.githubusercontent.com/UW-GAC/pgsc_calc_wdl/refs/heads/main/pgsc_calc_prepare_genomes.wdl" as prep
import "primed_calc_pgs.wdl" as this
import "https://raw.githubusercontent.com/UW-GAC/pgsc_calc_wdl/refs/heads/main/calc_scores.wdl" as calc

workflow pgs_calc_variant_file {
    input {
        Array[File]? vcf
        File? pgen
        File? pvar
        File? psam
        File scorefile
        String genome_build
        Float min_overlap
        String pgs_model_id
        String sampleset_name
        String dest_bucket
        String? primed_dataset_id
        Boolean ancestry_adjust
        File? pcs
    }

    if (defined(vcf)) {
        scatter (file in select_first([vcf, ""])) {
            call prep.prepare_genomes {
                input:
                    vcf = file
            }
        }

        call this.merge_files {
        input:
            pgen = prepare_genomes.pgen,
            pvar = prepare_genomes.pvar,
            psam = prepare_genomes.psam
        }
    }

    call this.match_scorefile {
        input:
            scorefile = scorefile,
            pvar = select_first([merge_files.out_pvar, pvar]),
            genome_build = genome_build,
            min_overlap = min_overlap,
            pgs_name = pgs_model_id,
            pgs_id = pgs_model_id,
            sampleset_name = sampleset_name
    }

    call this.plink_score {
        input:
            scorefile = match_scorefile.match_scorefile,
            pgen = select_first([merge_files.out_pgen, pgen]),
            pvar = select_first([merge_files.out_pvar, pvar]),
            psam = select_first([merge_files.out_psam, psam]),
            prefix = sampleset_name
    }

    if (ancestry_adjust) {
        call this.adjust_prs {
            input:
                scores = plink_score.scores,
                pcs = select_first([pcs, ""])
        }
    }

    call calc.chr_prefix {
        input:
            file = plink_score.variants
    }

    output {
        File match_log = match_scorefile.match_log
        File match_summary = match_scorefile.match_summary
        File score_file = plink_score.scores
        File variants = plink_score.variants
        File variant_chr_prefix = chr_prefix.outfile
        File? adjusted_score_file = adjust_prs.adjusted_scores
    }

     meta {
          author: "Stephanie Gogarten"
          email: "sdmorris@uw.edu"
     }
}
