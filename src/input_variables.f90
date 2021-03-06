!======================================================================
! The following lines have been generated by a python script: input_variables.py 
! Do not alter them directly: they will be overriden sooner or later by the script
! To add a new input variable, modify the script directly
! Generated by input_parameter.py on 18 January 2019
!======================================================================

 namelist /molgw/   &
    scf,       &
    postscf,       &
    move_nuclei,       &
    nstep,       &
    tolforce,       &
    alpha_hybrid,       &
    beta_hybrid,       &
    gamma_hybrid,       &
    basis,       &
    auxil_basis,       &
    incore,       &
    basis_path,       &
    small_basis,       &
    ecp_small_basis,       &
    gaussian_type,       &
    nspin,       &
    charge,       &
    magnetization,       &
    temperature,       &
    grid_quality,       &
    tddft_grid_quality,       &
    integral_quality,       &
    partition_scheme,       &
    nscf,       &
    alpha_mixing,       &
    mixing_scheme,       &
    diis_switch,       &
    level_shifting_energy,       &
    init_hamiltonian,       &
    tolscf,       &
    density_matrix_damping,       &
    kerker_k0,       &
    min_overlap,       &
    npulay_hist,       &
    scf_diago_flavor,       &
    postscf_diago_flavor,       &
    nstep_gw,       &
    tda,       &
    triplet,       &
    nexcitation,       &
    toldav,       &
    nstep_dav,       &
    frozencore,       &
    ncoreg,       &
    ncorew,       &
    nvirtualg,       &
    nvirtualw,       &
    nvirtualspa,       &
    nomega_imag,       &
    selfenergy_state_min,       &
    selfenergy_state_max,       &
    selfenergy_state_range,       &
    nomega_sigma,       &
    step_sigma,       &
    pt3_a_diagrams,       &
    pt_density_matrix,       &
    use_correlated_density_matrix,       &
    read_restart,       &
    ignore_bigrestart,       &
    force_energy_qp,       &
    print_hartree,       &
    print_density_matrix,       &
    print_rho_grid,       &
    print_eri,       &
    print_wfn,       &
    print_cube,       &
    read_fchk,       &
    print_w,       &
    print_restart,       &
    print_bigrestart,       &
    print_sigma,       &
    print_pdos,       &
    print_multipole,       &
    length_unit,       &
    natom,       &
    xyz_file,       &
    nghost,       &
    eta,       &
    scissor,       &
    grid_memory,       &
    scalapack_block_min,       &
    eri3_nprow,       &
    eri3_npcol,       &
    eri3_nbatch,       &
    scalapack_nprow,       &
    scalapack_npcol,       &
    mpi_nproc_ortho,       &
    alpha_cohsex,       &
    beta_cohsex,       &
    dft_core,       &
    gamma_cohsex,       &
    delta_cohsex,       &
    epsilon_cohsex,       &
    virtual_fno,       &
    rcut_mbpt,       &
    gwgamma_tddft,       &
    ecp_type,       &
    ecp_elements,       &
    ecp_quality,       &
    ecp_basis,       &
    ecp_auxil_basis,       &
    time_step,       &
    time_sim,       &
    prop_type,       &
    ci_greens_function,       &
    excit_name,       &
    ci_type,       &
    excit_kappa,       &
    ci_nstate,       &
    excit_omega,       &
    ci_nstate_self,       &
    excit_time0,       &
    ci_spin_multiplicity,       &
    excit_dir,       &
    print_tddft_matrices,       &
    print_cube_rho_tddft,       &
    print_line_rho_tddft,       &
    write_step,       &
    pred_corr,       &
    n_hist,       &
    n_iter,       &
    calc_spectrum,       &
    read_tddft_restart,       &
    print_tddft_restart,       &
    vel_projectile,       &
    n_restart_tddft,       &
    print_cube_diff_tddft,       &
    print_dens_traj_tddft,       &
    calc_q_matrix,       &
    print_dens_traj,       &
    calc_dens_disc,       &
    r_disc

!=====

 scf=''
 postscf=''
 move_nuclei='no'
 nstep=50
 tolforce=1e-05_dp 
 alpha_hybrid=0.0_dp 
 beta_hybrid=0.0_dp 
 gamma_hybrid=1000000.0_dp 
 basis=''
 auxil_basis=''
 incore='yes'
 basis_path=''
 small_basis=''
 ecp_small_basis=''
 gaussian_type='pure'
 nspin=1
 charge=0.0_dp 
 magnetization=0.0_dp 
 temperature=0.0_dp 
 grid_quality='high'
 tddft_grid_quality='high'
 integral_quality='high'
 partition_scheme='ssf'
 nscf=50
 alpha_mixing=0.7_dp 
 mixing_scheme='pulay'
 diis_switch=0.05_dp 
 level_shifting_energy=0.0_dp 
 init_hamiltonian='guess'
 tolscf=1e-07_dp 
 density_matrix_damping=0.0_dp 
 kerker_k0=0.0_dp 
 min_overlap=1e-05_dp 
 npulay_hist=6
 scf_diago_flavor=' '
 postscf_diago_flavor='R'
 nstep_gw=1
 tda='no'
 triplet='no'
 nexcitation=0
 toldav=0.0001_dp 
 nstep_dav=15
 frozencore='no'
 ncoreg=0
 ncorew=0
 nvirtualg=100000
 nvirtualw=100000
 nvirtualspa=100000
 nomega_imag=0
 selfenergy_state_min=1
 selfenergy_state_max=100000
 selfenergy_state_range=100000
 nomega_sigma=51
 step_sigma=0.01_dp 
 pt3_a_diagrams='yes'
 pt_density_matrix='no'
 use_correlated_density_matrix='no'
 read_restart='no'
 ignore_bigrestart='no'
 force_energy_qp='no'
 print_hartree='no'
 print_density_matrix='no'
 print_rho_grid='no'
 print_eri='no'
 print_wfn='no'
 print_cube='no'
 read_fchk='no'
 print_w='no'
 print_restart='yes'
 print_bigrestart='yes'
 print_sigma='no'
 print_pdos='no'
 print_multipole='no'
 length_unit='angstrom'
 natom=0
 xyz_file=''
 nghost=0
 eta=0.001_dp 
 scissor=0.0_dp 
 grid_memory=400.0_dp 
 scalapack_block_min=1000
 eri3_nprow=1
 eri3_npcol=1
 eri3_nbatch=1
 scalapack_nprow=1
 scalapack_npcol=1
 mpi_nproc_ortho=1
 alpha_cohsex=1.0_dp 
 beta_cohsex=1.0_dp 
 dft_core=0
 gamma_cohsex=0.0_dp 
 delta_cohsex=0.0_dp 
 epsilon_cohsex=0.0_dp 
 virtual_fno='no'
 rcut_mbpt=1.0_dp 
 gwgamma_tddft='no'
 ecp_type=''
 ecp_elements=''
 ecp_quality='high'
 ecp_basis=''
 ecp_auxil_basis=''
 time_step=1.0_dp 
 time_sim=10.0_dp 
 prop_type='CN'
 ci_greens_function='holes'
 excit_name='NO'
 ci_type='all'
 excit_kappa=2e-05_dp 
 ci_nstate=1
 excit_omega=0.2_dp 
 ci_nstate_self=1
 excit_time0=3.0_dp 
 ci_spin_multiplicity=1
 excit_dir=(/ 1.0_dp , 0.0_dp , 0.0_dp /)
 print_tddft_matrices='no'
 print_cube_rho_tddft='no'
 print_line_rho_tddft='no'
 write_step=1_dp 
 pred_corr='PC1'
 n_hist=2
 n_iter=2
 calc_spectrum='no'
 read_tddft_restart='no'
 print_tddft_restart='yes'
 vel_projectile=(/ 0.0_dp , 0.0_dp , 1.0_dp /)
 n_restart_tddft=50
 print_cube_diff_tddft='no'
 print_dens_traj_tddft='no'
 calc_q_matrix='no'
 print_dens_traj='no'
 calc_dens_disc='no'
 r_disc=200.0_dp 


!======================================================================
