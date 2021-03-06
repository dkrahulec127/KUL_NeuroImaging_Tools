#!/bin/bash -e
# Bash shell script to process diffusion & structural 3D-T1w MRI data
#  Developed for Segmentation of the Dentato-rubro-thalamic tract in thalamus for DBS target selection
#   following the paper "Connectivity derived thalamic segmentation in deep brain stimulation for tremor"
#       of Akram et al. 2018 (https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5790021/pdf/main.pdf)
#  Project PI's: Stefan Sunaert & Bart Nuttin
#
# Requires Mrtrix3, FSL, ants, freesurfer
#
# @ Stefan Sunaert - UZ/KUL - stefan.sunaert@uzleuven.be
#
# v0.1 - dd 11/10/2018 - alpha version
v="v0.1 - dd 11/10/2018"

# To Do
#  - use 5ttgen with freesurfer
#  - register dwi to T1 with ants-syn
#  - fod calc msmt-5tt in stead of dhollander
#  - use HPC of KUL?
#  - how to import in neuronavigation?
#  - warp the resulted TH-* back into MNI space for group analysis 


# A few fixed (for now) parameters:

    # Number of desired streamlines
    nods=20000

    # tmp directory for temporary processing
    tmp=/tmp
# 


# -----------------------------------  MAIN  ---------------------------------------------
# this script defines a few functions:
#  - Usage (for information to the novice user)
#  - kul_e2cl (for logging)
#  - dcmtags (for reading specific parameters from dicom header)
#
# this script uses "preprocessing control", i.e. if some steps are already processed it will skip these

kul_main_dir=`dirname "$0"`
source $kul_main_dir/KUL_main_functions.sh
cwd=$(pwd)

# FUNCTIONS --------------

# function Usage
function Usage {

cat <<USAGE

`basename $0` performs dMRI segmentation of the Dentato-rubro-thalamic tract in thalamus for DBS target selection.

Usage:

  `basename $0` -s subject <OPT_ARGS>

Example:

  `basename $0` -s pat001 -p 6 

Required arguments:

     -s:  subject (anonymised name of the subject)

Optional arguments:

     -p:  number of cpu for parallelisation
     -v:  show output from mrtrix commands


USAGE

    exit 1
}


# CHECK COMMAND LINE OPTIONS -------------
# 
# Set defaults
ncpu=6
silent=1

# Set required options
s_flag=0

if [ "$#" -lt 1 ]; then
    Usage >&2
    exit 1

else

    while getopts "s:p:vh" OPT; do

        case $OPT in
        s) #subject
            s_flag=1
            subj=$OPTARG
        ;;
        p) #parallel
            ncpu=$OPTARG
        ;;
        v) #verbose
            silent=0
        ;;
        h) #help
            Usage >&2
            exit 0
        ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo
            Usage >&2
            exit 1
        ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            echo
            Usage >&2
            exit 1
        ;;
        esac

    done

fi

# check for required options
if [ $s_flag -eq 0 ] ; then 
    echo 
    echo "Option -s is required: give the anonymised name of a subject." >&2
    echo
    exit 2 
fi 


# MRTRIX verbose or not?
if [ $silent -eq 1 ] ; then 

    export MRTRIX_QUIET=1

fi

# REST OF SETTINGS ---

# timestamp
start=$(date +%s)

# Some parallelisation
FSLPARALLEL=$ncpu; export FSLPARALLEL
OMP_NUM_THREADS=$ncpu; export OMP_NUM_THREADS

# Directory to write preprocessed data in
preproc=dwiprep/sub-${subj}

d=$(date "+%Y-%m-%d_%H-%M-%S")
log=log/log_${d}.txt



# SAY HELLO ---

kul_e2cl "Welcome to KUL_dwi_preproc $v - $d" ${preproc}/${log}


# STEP 1 - PROCESSING  ---------------------------------------------
cd ${preproc}

# Where is the freesurfer parcellation? 
fs_aparc=${cwd}/freesurfer/sub-${subj}/${subj}/mri/aparc+aseg.mgz

# Where is the T1w anat?
ants_anat=T1w/T1w_BrainExtractionBrain.nii.gz

# Convert FS aparc back to original space
mkdir -p roi
fs_labels=roi/labels_from_FS.nii.gz
if [ ! -f $fs_labels ]; then
    mri_convert -rl $ants_anat -rt nearest $fs_aparc $fs_labels
fi

# 5tt segmentation & tracking
mkdir -p 5tt

if [ ! -f 5tt/5tt2gmwmi.nii.gz ]; then

    kul_e2cl " Performig 5tt..." ${log}
    #5ttgen fsl $ants_anat 5tt/5ttseg.mif -premasked -nocrop -force -nthreads $ncpu 
    #5ttgen freesurfer $fs_aparc 5tt/5ttseg.mif -nocrop -force -nthreads $ncpu
    5ttgen freesurfer $fs_labels 5tt/5ttseg.mif -nocrop -force -nthreads $ncpu
    
    5ttcheck -masks 5tt/failed_5tt 5tt/5ttseg.mif -force -nthreads $ncpu 
    5tt2gmwmi 5tt/5ttseg.mif 5tt/5tt2gmwmi.nii.gz -force 

else

    echo " 5tt already done, skipping..."

fi

# Extract relevant freesurfer determined rois
if [ ! -f roi/WM_fs_R.nii.gz ]; then

    kul_e2cl " Making the Freesurfer ROIS from subject space..." ${log}

    # M1_R is 2024
    fslmaths $fs_labels -thr 2024 -uthr 2024 -bin roi/M1_fs_R
    # M1_L is 1024
    fslmaths $fs_labels -thr 1024 -uthr 1024 -bin roi/M1_fs_L
    # S1_R is 2022
    fslmaths $fs_labels -thr 2022 -uthr 2022 -bin roi/S1_fs_R
    # S1_L is 1024
    fslmaths $fs_labels -thr 1022 -uthr 1022 -bin roi/S1_fs_L
    # Thalamus_R is 49
    fslmaths $fs_labels -thr 49 -uthr 49 -bin roi/THALAMUS_fs_R
    # Thalamus_L is 10
    fslmaths $fs_labels -thr 10 -uthr 10 -bin roi/THALAMUS_fs_L
    # SMA_and_PMC_L are
    # 1003    ctx-lh-caudalmiddlefrontal
    # 1028    ctx-lh-superiorfrontal
    fslmaths $fs_labels -thr 1003 -uthr 1003 -bin roi/MFG_fs_R
    fslmaths $fs_labels -thr 1028 -uthr 1028 -bin roi/SFG_fs_R
    fslmaths roi/MFG_fs_R -add roi/SFG_fs_R -bin roi/SMA_and_PMC_fs_R
    # SMA_and_PMC_L are
    # 2003    ctx-lh-caudalmiddlefrontal
    # 2028    ctx-lh-superiorfrontal
    fslmaths $fs_labels -thr 2003 -uthr 2003 -bin roi/MFG_fs_L
    fslmaths $fs_labels -thr 2028 -uthr 2028 -bin roi/SFG_fs_L
    fslmaths roi/MFG_fs_L -add roi/SFG_fs_L -bin roi/SMA_and_PMC_fs_L
    # 41  Right-Cerebral-White-Matter
    fslmaths $fs_labels -thr 41 -uthr 41 -bin roi/WM_fs_R
    # 2   Left-Cerebral-White-Matter
    fslmaths $fs_labels -thr 2 -uthr 2 -bin roi/WM_fs_L


else

echo " Making the Freesurfer ROIS has been done already, skipping" 

fi

# transform the T1w into MNI space using fmriprep data

MNI_transform=${cwd}/fmriprep/fmriprep/sub-${subj}/anat/sub-${subj}_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5
reference=/KUL_apps/fsl/data/standard/MNI152_T1_1mm.nii.gz

# Apply fmriprep MNI normalisation 
antsApplyTransforms -d 3 --float 1 \
--verbose 1 \
-i $ants_anat \
-o T1w/T1w_MNI152NLin2009cAsym.nii.gz \
-r $reference \
-t $MNI_transform \
-n Linear


# transform the T1w into MNI space using fmriprep data

input=${cwd}/fmriprep/fmriprep/sub-${subj}/anat/sub-${subj}_space-MNI152NLin2009cAsym_desc-preproc_T1w.nii.gz
MNI_transform=${cwd}/fmriprep/fmriprep/sub-${subj}/anat/sub-${subj}_from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5
reference=$ants_anat

# Apply fmriprep MNI normalisation 
antsApplyTransforms -d 3 --float 1 \
--verbose 1 \
-i $input \
-o T1w/T1w_test_inv_MNI_warp.nii.gz \
-r $reference \
-t $MNI_transform \
-n Linear

# We get the Dentate rois out of MNI space, from the SUIT v3.3 atlas
# http://www.diedrichsenlab.org/imaging/suit_download.htm
# fslmaths Cerebellum-SUIT.nii -thr 30 -uthr 30 Dentate_R
# fslmaths Cerebellum-SUIT.nii -thr 29 -uthr 29 Dentate_L

input=${kul_main_dir}/atlasses/Local/Dentate_R.nii.gz
output=roi/DENTATE_R.nii.gz
MNI_transform=${cwd}/fmriprep/fmriprep/sub-${subj}/anat/sub-${subj}_from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5
reference=$ants_anat

# Apply fmriprep MNI normalisation 
antsApplyTransforms -d 3 --float 1 \
--verbose 1 \
-i $input \
-o $output \
-r $reference \
-t $MNI_transform \
-n Linear

input=${kul_main_dir}/atlasses/Local/Dentate_L.nii.gz
output=roi/DENTATE_L.nii.gz
MNI_transform=${cwd}/fmriprep/fmriprep/sub-${subj}/anat/sub-${subj}_from-MNI152NLin2009cAsym_to-T1w_mode-image_xfm.h5
reference=$ants_anat

# Apply fmriprep MNI normalisation 
antsApplyTransforms -d 3 --float 1 \
--verbose 1 \
-i $input \
-o $output \
-r $reference \
-t $MNI_transform \
-n Linear


# STEP 5 - Tractography Processing ---------------------------------------------

function kul_mrtrix_tracto_drt {

    for a in iFOD2 Tensor_Prob; do

        if [ ! -f ${tract}_${a}.nii.gz ]; then

            mkdir -p tracts_${a}

            # make the intersect string (this is the first of the seeds)
            intersect=${seeds%% *}

            kul_e2cl " Calculating $a ${tract} tract (all seeds with -select $nods, intersect with $intersect)" ${log} 

            # make the seed string
            local s=$(printf " -seed_image roi/%s.nii.gz"  "${seeds[@]}")
    
            # make the include string (which is same rois as seed)
            local i=$(printf " -include roi/%s.nii.gz"  "${seeds[@]}")

            # make the exclude string (which is same rois as seed)
            local e=$(printf " -exclude roi/%s.nii.gz"  "${exclude[@]}")

            # make the mask string 
            local m="-mask dwi_mask.nii.gz"

            if [ "${a}" == "iFOD2" ]; then

                # perform IFOD2 tckgen
                tckgen $wmfod tracts_${a}/${tract}.tck -algorithm $a -select $nods $s $i $e $m -nthreads $ncpu -force

            else

                # perform Tensor_Prob tckgen
                tckgen $dwi_preproced tracts_${a}/${tract}.tck -algorithm $a -cutoff 0.01 -select $nods $s $i $e $m -nthreads $ncpu -force

            fi

            # convert the tck in nii
            tckmap tracts_${a}/${tract}.tck tracts_${a}/${tract}.nii.gz -template $ants_anat -force 

            # intersect the nii tract image with the thalamic roi
            fslmaths tracts_${a}/${tract}.nii -mas roi/${intersect}.nii.gz tracts_${a}/${tract}_masked
    
            # make a probabilistic image
            local m=$(mrstats -quiet tracts_${a}/${tract}_masked.nii.gz -output max)
            fslmaths tracts_${a}/${tract}_masked -div $m ${tract}_${a}

        fi
    
    done

}

wmfod=response/wmfod_reg2T1w.mif
dwi_preproced=dwi_preproced_reg2T1w.mif

# M1_fs-Thalamic tracts
tract="TH-M1_fs_R"
seeds=("THALAMUS_fs_R" "M1_fs_R")
exclude="WM_fs_L"
kul_mrtrix_tracto_drt 

tract="TH-M1_fs_L"
seeds=("THALAMUS_fs_L" "M1_fs_L")
exclude="WM_fs_R"
kul_mrtrix_tracto_drt 

# S1_fs-Thalamic tracts
tract="TH-S1_fs_R"
seeds=("THALAMUS_fs_R" "S1_fs_R")
exclude="WM_fs_L"
kul_mrtrix_tracto_drt 

tract="TH-S1_fs_L"
seeds=("THALAMUS_fs_L" "S1_fs_L")
exclude="WM_fs_R"
kul_mrtrix_tracto_drt 

# SMA_and_PMC-Thalamic tracts
tract="TH-SMA_and_PMC_R"
seeds=("THALAMUS_fs_R" "SMA_and_PMC_fs_L")
exclude="WM_fs_L"
kul_mrtrix_tracto_drt 

tract="TH-SMA_and_PMC_L"
seeds=("THALAMUS_fs_L" "SMA_and_PMC_fs_L")
kul_mrtrix_tracto_drt  

# Dentato-Rubro_Thalamic tracts
tract="TH-DR_R"
seeds=("THALAMUS_fs_R" "M1_fs_R" "DENTATE_L")
exclude="WM_fs_L"
kul_mrtrix_tracto_drt 

tract="TH-DR_L"
seeds=("THALAMUS_fs_L" "M1_fs_L" "DENTATE_R")
exclude="WM_fs_R"
kul_mrtrix_tracto_drt 

kul_e2cl "KUL_dwi_preproc $v - finished processing" ${log}

exit 0

# M1-Thalamic tracts
tract="TH-M1_R"
seeds=("THALAMUS_R" "M1")
exclude="WM_fs_L"
kul_mrtrix_tracto_drt 

tract="TH-M1_L"
seeds=("THALAMUS_L" "M1")
exclude="WM_fs_R"
kul_mrtrix_tracto_drt 

# S1-Thalamic tracts
tract="TH-S1_R"
seeds=("THALAMUS_R" "S1")
exclude="WM_fs_L"
kul_mrtrix_tracto_drt 

tract="TH-S1_L"
seeds=("THALAMUS_L" "S1")
exclude="WM_fs_R"
kul_mrtrix_tracto_drt 

# SMA_and_PMC-Thalamic tracts
tract="TH-SMA_and_PMC_R"
seeds=("THALAMUS_R" "SMA_and_PMC")
exclude="WM_fs_L"
kul_mrtrix_tracto_drt 

tract="TH-SMA_and_PMC_L"
seeds=("THALAMUS_L" "SMA_and_PMC")
exclude="WM_fs_R"
kul_mrtrix_tracto_drt  


# STEP 5 - ROI Processing ---------------------------------------------
mkdir -p roi





# Warp the MNI ROIS into subject space (apply INVERSE warp using ants)
if [ ! -f atlas/TH-SMA_R.nii.gz ]; then
kul_e2cl " Warping the MNI ROIS into subjects space..." ${log}
WarpImageMultiTransform 3 ../ROIS/ROI_DENTATE_L.nii.gz roi/DENTATE_L.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/ROI_DENTATE_R.nii.gz roi/DENTATE_R.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/ROI_THALAMUS_L.nii.gz roi/THALAMUS_L.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/ROI_THALAMUS_R.nii.gz roi/THALAMUS_R.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/ROI_M1.nii.gz roi/M1_full.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz \
    -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/ROI_S1.nii.gz roi/S1_full.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz \
    -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/ROI_SMA_and_PMC.nii.gz roi/SMA_and_PMC_full.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz \
    -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 

# transect the S1, M1 and SMA_and_PMC ROIS with 5ttgen wm/gm interface
kul_e2cl " Intersecting ROIS with 5tt WM/GM..." ${log}
WarpImageMultiTransform 3 5tt/5tt2gmwmi.nii.gz 5tt/5tt2gmwmi_dwi.nii.gz -R roi/M1_full.nii.gz --reslice-by-header
fslmaths roi/M1_full.nii.gz -mas 5tt/5tt2gmwmi_dwi.nii.gz roi/M1.nii.gz
fslmaths roi/S1_full.nii.gz -mas 5tt/5tt2gmwmi_dwi.nii.gz roi/S1.nii.gz
fslmaths roi/SMA_and_PMC_full.nii.gz -mas 5tt/5tt2gmwmi_dwi.nii.gz roi/SMA_and_PMC.nii.gz

# Warp the Atlas ROIS into subjects space (apply INVERSE warp using ants)
mkdir -p atlas
kul_e2cl " Warping the Atlas ROIS into subjects space..." ${log}
WarpImageMultiTransform 3 ../ROIS/Thalamic_DBS_Connectivity_atlas_Akram_2018/lh/Dentate.nii.gz atlas/TH-Dentate_L.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/Thalamic_DBS_Connectivity_atlas_Akram_2018/lh/M1.nii.gz atlas/TH-M1_L.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/Thalamic_DBS_Connectivity_atlas_Akram_2018/lh/S1.nii.gz atlas/TH-S1_L.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/Thalamic_DBS_Connectivity_atlas_Akram_2018/lh/SMA.nii.gz atlas/TH-SMA_L.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 

WarpImageMultiTransform 3 ../ROIS/Thalamic_DBS_Connectivity_atlas_Akram_2018/rh/Dentate.nii.gz atlas/TH-Dentate_R.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/Thalamic_DBS_Connectivity_atlas_Akram_2018/rh/M1.nii.gz atlas/TH-M1_R.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/Thalamic_DBS_Connectivity_atlas_Akram_2018/rh/S1.nii.gz atlas/TH-S1_R.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 
WarpImageMultiTransform 3 ../ROIS/Thalamic_DBS_Connectivity_atlas_Akram_2018/rh/SMA.nii.gz atlas/TH-SMA_R.nii.gz -R T1w/T1w_brain_reg2_b0_deformed.nii.gz -i T1w/T1w_brain_reg2_b0_MNI_0GenericAffine.mat T1w/T1w_brain_reg2_b0_MNI_1InverseWarp.nii.gz 

else

echo " Reverse warping of rois/atlas has been done already, skipping" 

fi
