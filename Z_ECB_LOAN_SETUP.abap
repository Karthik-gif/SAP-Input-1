*&---------------------------------------------------------------------*
*& Report  : Z_ECB_LOAN_SETUP
*& Package : ZCO_ECB_LOAN
*& Version : 1.0.0
*&---------------------------------------------------------------------*
*& Purpose : ONE-CLICK INSTALLER for the ECB Loan Management application.
*&
*&   Automates creation of ALL SAP objects required:
*&     [1] ABAP Package         ZCO_ECB_LOAN
*&     [2] Number Range Object  ZCO_LOAN  (intervals 01)
*&     [3] Message Class        ZCO_ECB_LOAN  (30 messages)
*&     [4] MIME Repository      /SAP/PUBLIC/ECB_LOAN/ folder + HTML upload
*&     [5] OData Service        ZCO_ECB_LOAN_SRV registration
*&     [6] Customising entries  Product Type / Transaction Type tables
*&
*&   Objects that CANNOT be created programmatically (must be done manually):
*&     - DDIC Table ZECB_LOAN_HDR      → SE11
*&     - DDIC Structures ZST_*         → SE11
*&     - SEGW OData project            → SEGW (then run this report for reg.)
*&     - GUI Status MAIN               → SE41
*&     - Screen 0100 layout            → SE51
*&     (These are transport-based; use abapGit to deploy — see .abapgit.xml)
*&
*& Usage:
*&   Run in development system first, then transport via CTS.
*&   Each step is idempotent — safe to re-run without duplicating objects.
*&
*& Transaction: SE93 → Program → Z_ECB_LOAN_SETUP
*&---------------------------------------------------------------------*
REPORT z_ecb_loan_setup.

*----------------------------------------------------------------------*
*  Types
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_step_result,
         step    TYPE i,
         name    TYPE string,
         status  TYPE string,    " OK / SKIP / ERROR / WARN
         message TYPE string,
       END OF ty_step_result.

*----------------------------------------------------------------------*
*  Global data
*----------------------------------------------------------------------*
DATA: gt_results  TYPE STANDARD TABLE OF ty_step_result,
      gv_devclass TYPE devclass VALUE 'ZCO_ECB_LOAN',
      gv_corr     TYPE trkorr.   " Transport request

*----------------------------------------------------------------------*
*  Selection screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS:
    p_pkg   TYPE devclass DEFAULT 'ZCO_ECB_LOAN',
    p_corr  TYPE trkorr   OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS:
    p_mime  AS CHECKBOX DEFAULT 'X',   " Upload HTML to MIME
    p_nrng  AS CHECKBOX DEFAULT 'X',   " Create number range
    p_msgs  AS CHECKBOX DEFAULT 'X',   " Create message class entries
    p_odat  AS CHECKBOX DEFAULT 'X',   " Register OData service
    p_cust  AS CHECKBOX DEFAULT 'X'.   " Insert customising entries
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
*  START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  gv_devclass = p_pkg.
  gv_corr     = p_corr.

  WRITE: / '═══════════════════════════════════════════════════════════'.
  WRITE: / ' ECB LOAN MANAGEMENT — AUTOMATED SETUP v1.0'.
  WRITE: / '═══════════════════════════════════════════════════════════'.
  WRITE: /.

  PERFORM step_package.
  IF p_nrng = 'X'. PERFORM step_number_range.  ENDIF.
  IF p_msgs = 'X'. PERFORM step_message_class. ENDIF.
  IF p_mime = 'X'. PERFORM step_mime_upload.   ENDIF.
  IF p_odat = 'X'. PERFORM step_odata_service. ENDIF.
  IF p_cust = 'X'. PERFORM step_customising.   ENDIF.

  PERFORM display_summary.

*======================================================================*
*  STEP 1 — ABAP Package
*======================================================================*
FORM step_package.
  DATA: ls_result TYPE ty_step_result.
  ls_result-step = 1.
  ls_result-name = 'ABAP Package ZCO_ECB_LOAN'.

  " Check if package exists
  SELECT SINGLE devclass FROM tdevc
    INTO @DATA(lv_pkg)
    WHERE devclass = @gv_devclass.

  IF sy-subrc = 0.
    ls_result-status  = 'SKIP'.
    ls_result-message = 'Package already exists'.
  ELSE.
    " Create package using CL_PACKAGE_FACTORY
    DATA: lo_package  TYPE REF TO if_package,
          lo_requests TYPE REF TO if_package_requests,
          lv_msg      TYPE string.

    TRY.
        cl_package_factory=>create_new_package(
          EXPORTING
            iv_package_name         = gv_devclass
            iv_short_text           = 'ECB Loan Management'
            iv_software_component   = 'LOCAL'  " Change to your SW component
            iv_transport_layer      = '$TMP'   " Change to your layer
          IMPORTING
            ev_package              = lo_package
          EXCEPTIONS
            object_already_existing = 1
            OTHERS                  = 2 ).

        IF sy-subrc = 0.
          lo_package->save(
            iv_with_corrnr        = abap_true
            iv_corrtype           = 'K'
            iv_corrnr             = gv_corr ).
          lo_package->activate( ).
          ls_result-status  = 'OK'.
          ls_result-message = 'Package created and activated'.
        ELSEIF sy-subrc = 1.
          ls_result-status  = 'SKIP'.
          ls_result-message = 'Package already exists'.
        ELSE.
          ls_result-status  = 'ERROR'.
          ls_result-message = 'Package creation failed (RC=' && sy-subrc && ')'.
        ENDIF.

      CATCH cx_root INTO DATA(lx).
        ls_result-status  = 'ERROR'.
        ls_result-message = lx->get_text( ).
    ENDTRY.
  ENDIF.

  APPEND ls_result TO gt_results.
  PERFORM log_step USING ls_result.
ENDFORM.

*======================================================================*
*  STEP 2 — Number Range Object ZCO_LOAN
*======================================================================*
FORM step_number_range.
  DATA: ls_result  TYPE ty_step_result,
        lt_interval TYPE STANDARD TABLE OF nriv_x.

  ls_result-step = 2.
  ls_result-name = 'Number Range Object ZCO_LOAN'.

  " Check if object already exists
  CALL FUNCTION 'NUMBER_RANGE_READ'
    EXPORTING  object = 'ZCO_LOAN'
    EXCEPTIONS OTHERS = 4.

  IF sy-subrc = 0.
    ls_result-status  = 'SKIP'.
    ls_result-message = 'Number range object already exists'.
    APPEND ls_result TO gt_results.
    PERFORM log_step USING ls_result.
    RETURN.
  ENDIF.

  " Create number range object
  CALL FUNCTION 'NUMBERRANGE_OBJECT_CREATE'
    EXPORTING
      object     = 'ZCO_LOAN'
      domlen     = 10
      txt        = 'ECB Loan ID Number Range'
      devclass   = gv_devclass
      korr       = gv_corr
    EXCEPTIONS
      already_exists = 1
      OTHERS         = 2.

  IF sy-subrc > 1.
    ls_result-status  = 'ERROR'.
    ls_result-message = 'Object creation failed (RC=' && sy-subrc && ')'.
    APPEND ls_result TO gt_results.
    PERFORM log_step USING ls_result.
    RETURN.
  ENDIF.

  " Insert interval 01: 0000000001 → 9999999999
  APPEND VALUE #(
    nrrangenr = '01'
    fromnumber = '0000000001'
    tonumber   = '9999999999'
    nrlevel    = '0000000000'
    externind  = ''
  ) TO lt_interval.

  CALL FUNCTION 'NUMBER_RANGE_INTERVAL_INSERT'
    EXPORTING  object    = 'ZCO_LOAN'
    TABLES     interval  = lt_interval
    EXCEPTIONS OTHERS    = 1.

  IF sy-subrc = 0.
    ls_result-status  = 'OK'.
    ls_result-message = 'Object created — interval 01: 0000000001 to 9999999999'.
  ELSE.
    ls_result-status  = 'WARN'.
    ls_result-message = 'Object created but interval insert failed — set manually in SNRO'.
  ENDIF.

  APPEND ls_result TO gt_results.
  PERFORM log_step USING ls_result.
ENDFORM.

*======================================================================*
*  STEP 3 — Message Class ZCO_ECB_LOAN
*======================================================================*
FORM step_message_class.
  DATA: ls_result TYPE ty_step_result,
        lt_msgs   TYPE STANDARD TABLE OF t100,
        ls_msg    TYPE t100.

  ls_result-step = 3.
  ls_result-name = 'Message Class ZCO_ECB_LOAN'.

  " Message definitions — matches ZCL_ECB_LOAN_DPC_EXT usage
  DATA(lt_message_defs) = VALUE t100tab(
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '000' text = '& & & &' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '001' text = 'Loan ID is required' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '002' text = 'Loan & not found' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '003' text = 'Company Code & does not exist in T001' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '004' text = 'Facility & not found for Co Code &' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '005' text = 'Drawdown amount exceeds available facility limit' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '006' text = 'Database insert failed for loan record' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '007' text = 'Loan & created successfully' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '008' text = 'Loan & cannot be modified (status Matured/Cancelled)' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '009' text = 'Database update failed for loan &' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '010' text = 'Required field & is missing' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '011' text = 'Loan Amount must be greater than zero' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '020' text = 'Facility keys Bukrs and FacilityId are required' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '021' text = 'Facility & not found for Co Code &' )
    ( sprsl = sy-langu arbgb = 'ZCO_ECB_LOAN' msgnr = '030' text = 'Number range object ZCO_LOAN error — check SNRO' )
  ).

  " Create message class header (T100A)
  DATA: ls_t100a TYPE t100a.
  ls_t100a-arbgb = 'ZCO_ECB_LOAN'.
  ls_t100a-stext = 'ECB Loan Management Messages'.
  ls_t100a-masterlang = sy-langu.
  MODIFY t100a FROM ls_t100a.

  " Insert/update message texts (T100)
  MODIFY t100 FROM TABLE lt_message_defs.

  IF sy-subrc = 0.
    " Add to transport
    DATA: lt_e071   TYPE STANDARD TABLE OF e071,
          lt_e071k  TYPE STANDARD TABLE OF e071k.

    APPEND VALUE #(
      pgmid    = 'R3TR'
      object   = 'MSAG'
      obj_name = 'ZCO_ECB_LOAN'
    ) TO lt_e071.

    CALL FUNCTION 'TR_APPEND_TO_COMM_OBJ'
      EXPORTING  iv_trkorr  = gv_corr
      TABLES     it_e071    = lt_e071
                 it_e071k   = lt_e071k
      EXCEPTIONS OTHERS     = 1.

    ls_result-status  = 'OK'.
    ls_result-message = 15 && ' message entries created/updated'.
  ELSE.
    ls_result-status  = 'ERROR'.
    ls_result-message = 'T100 MODIFY failed (RC=' && sy-subrc && ')'.
  ENDIF.

  APPEND ls_result TO gt_results.
  PERFORM log_step USING ls_result.
ENDFORM.

*======================================================================*
*  STEP 4 — MIME Repository: folder + HTML upload
*======================================================================*
FORM step_mime_upload.
  DATA: ls_result   TYPE ty_step_result,
        lo_mr_api   TYPE REF TO if_mr_api,
        lv_url      TYPE string,
        lv_content  TYPE xstring,
        lv_mimetype TYPE string,
        lv_exists   TYPE abap_bool.

  ls_result-step = 4.
  ls_result-name = 'MIME Repository — HTML Upload'.

  lv_url      = '/SAP/PUBLIC/ECB_LOAN/ECB_Loan_Management.html'.
  lv_mimetype = 'text/html'.

  TRY.
      " Get MIME repository API instance
      lo_mr_api = cl_mime_repository_api=>get_api( ).

      " Check if file already exists
      lo_mr_api->get(
        EXPORTING  i_url       = lv_url
        IMPORTING  e_content   = lv_content
        EXCEPTIONS OTHERS      = 1 ).

      IF sy-subrc = 0 AND lv_content IS NOT INITIAL.
        lv_exists = abap_true.
      ENDIF.

      " Read HTML content from application server (if placed in /tmp)
      " OR: embed the HTML inline below as a string literal
      " For production: upload the file to AL11 path first, then read here.

      DATA: lv_html TYPE string.

      " Option A: Read from application server file (upload via AL11 first)
      DATA: lt_lines TYPE STANDARD TABLE OF string,
            lv_as_path TYPE string VALUE '/tmp/ECB_Loan_Management.html'.

      OPEN DATASET lv_as_path FOR INPUT IN TEXT MODE ENCODING DEFAULT.
      IF sy-subrc = 0.
        DO.
          DATA: lv_line TYPE string.
          READ DATASET lv_as_path INTO lv_line.
          IF sy-subrc <> 0. EXIT. ENDIF.
          APPEND lv_line TO lt_lines.
        ENDDO.
        CLOSE DATASET lv_as_path.

        " Concatenate lines into single string
        LOOP AT lt_lines INTO lv_line.
          lv_html = lv_html && lv_line && cl_abap_char_utilities=>newline.
        ENDLOOP.

        " Convert string to xstring
        cl_abap_conv_codepage=>create_out( codepage = 'UTF-8' )->convert(
          EXPORTING source = lv_html
          IMPORTING data   = lv_content ).

        " Upload to MIME repository
        IF lv_exists = abap_true.
          lo_mr_api->put(
            EXPORTING
              i_url          = lv_url
              i_content      = lv_content
              i_mime_type    = lv_mimetype
              i_comment      = 'ECB Loan UI v2.0'
            EXCEPTIONS
              OTHERS         = 1 ).
        ELSE.
          lo_mr_api->put(
            EXPORTING
              i_url          = lv_url
              i_content      = lv_content
              i_mime_type    = lv_mimetype
              i_comment      = 'ECB Loan UI v2.0 — initial upload'
            EXCEPTIONS
              OTHERS         = 1 ).
        ENDIF.

        IF sy-subrc = 0.
          ls_result-status  = COND #( WHEN lv_exists = abap_true THEN 'OK' ELSE 'OK' ).
          ls_result-message = COND #(
            WHEN lv_exists = abap_true
            THEN 'HTML updated in MIME: ' && lv_url
            ELSE 'HTML uploaded to MIME: ' && lv_url ).
        ELSE.
          ls_result-status  = 'ERROR'.
          ls_result-message = 'MIME PUT failed (RC=' && sy-subrc && ')'.
        ENDIF.

      ELSE.
        ls_result-status  = 'WARN'.
        ls_result-message = 'HTML file not found at ' && lv_as_path &&
                            '. Upload file to AL11 path first, then re-run.'.
      ENDIF.

    CATCH cx_root INTO DATA(lx).
      ls_result-status  = 'ERROR'.
      ls_result-message = lx->get_text( ).
  ENDTRY.

  APPEND ls_result TO gt_results.
  PERFORM log_step USING ls_result.
ENDFORM.

*======================================================================*
*  STEP 5 — OData Service Registration
*======================================================================*
FORM step_odata_service.
  DATA: ls_result     TYPE ty_step_result,
        lv_svc_name   TYPE /iwfnd/med_ser_name VALUE 'ZCO_ECB_LOAN',
        lv_svc_ver    TYPE /iwfnd/med_ser_vers VALUE 1,
        lv_sys_alias  TYPE /iwfnd/sxms_conf_alias VALUE 'LOCAL'.

  ls_result-step = 5.
  ls_result-name = 'OData Service ZCO_ECB_LOAN_SRV Registration'.

  " Check if service already registered
  SELECT SINGLE srvdocid FROM /iwfnd/i_med_serdoc
    INTO @DATA(lv_check)
    WHERE srvdocname = @lv_svc_name
      AND srvdocvers = @lv_svc_ver.

  IF sy-subrc = 0.
    ls_result-status  = 'SKIP'.
    ls_result-message = 'Service already registered — skip'.
    APPEND ls_result TO gt_results.
    PERFORM log_step USING ls_result.
    RETURN.
  ENDIF.

  " Attempt programmatic registration via /IWFND/CL_SOD_MGMT
  " Note: SEGW project must be generated BEFORE running this step.
  TRY.
      DATA(lo_reg) = NEW /iwfnd/cl_sod_mgmt( ).

      lo_reg->register_service(
        EXPORTING
          iv_service_name           = lv_svc_name
          iv_service_version        = lv_svc_ver
          iv_system_alias           = lv_sys_alias
          iv_enable_batch           = abap_true
          iv_enable_changelog       = abap_true
          iv_enable_default_prefix  = abap_true
        EXCEPTIONS
          service_not_found         = 1
          system_alias_not_found    = 2
          already_registered        = 3
          OTHERS                    = 4 ).

      CASE sy-subrc.
        WHEN 0.
          ls_result-status  = 'OK'.
          ls_result-message = 'Service ZCO_ECB_LOAN_SRV registered on alias LOCAL'.
        WHEN 3.
          ls_result-status  = 'SKIP'.
          ls_result-message = 'Service already registered'.
        WHEN 1.
          ls_result-status  = 'WARN'.
          ls_result-message = 'Service not found — generate SEGW project first, then re-run'.
        WHEN OTHERS.
          ls_result-status  = 'WARN'.
          ls_result-message = 'Auto-registration failed (RC=' && sy-subrc &&
                              '). Register manually in /IWFND/MAINT_SERVICE'.
      ENDCASE.

    CATCH cx_root INTO DATA(lx).
      ls_result-status  = 'WARN'.
      ls_result-message = 'Exception: ' && lx->get_text( ) &&
                          ' — Register manually in /IWFND/MAINT_SERVICE'.
  ENDTRY.

  APPEND ls_result TO gt_results.
  PERFORM log_step USING ls_result.
ENDFORM.

*======================================================================*
*  STEP 6 — Customising: Product Type + Transaction Type entries
*======================================================================*
FORM step_customising.
  DATA: ls_result TYPE ty_step_result.
  ls_result-step = 6.
  ls_result-name = 'Customising Entries (Product & Transaction Types)'.

  " Product Type entries for ZTECB_PROD_TYPE
  DATA: lt_prod TYPE STANDARD TABLE OF ztecb_prod_type.
  APPEND VALUE #( mandt='*' prodtp='ECB'  description='External Commercial Borrowing'    sort_order=1 active=abap_true ) TO lt_prod.
  APPEND VALUE #( mandt='*' prodtp='FCCB' description='Foreign Currency Convertible Bond' sort_order=2 active=abap_true ) TO lt_prod.
  APPEND VALUE #( mandt='*' prodtp='TL'   description='Term Loan'                         sort_order=3 active=abap_true ) TO lt_prod.
  APPEND VALUE #( mandt='*' prodtp='RCF'  description='Revolving Credit Facility'         sort_order=4 active=abap_true ) TO lt_prod.
  APPEND VALUE #( mandt='*' prodtp='SNRN' description='Senior Notes'                      sort_order=5 active=abap_true ) TO lt_prod.

  " Transaction Type entries for ZTECB_TXN_TYPE
  DATA: lt_txn TYPE STANDARD TABLE OF ztecb_txn_type.
  APPEND VALUE #( mandt='*' txntype='DRAW' description='Drawdown'         sort_order=1 active=abap_true ) TO lt_txn.
  APPEND VALUE #( mandt='*' txntype='RPMT' description='Repayment'        sort_order=2 active=abap_true ) TO lt_txn.
  APPEND VALUE #( mandt='*' txntype='INT'  description='Interest Payment'  sort_order=3 active=abap_true ) TO lt_txn.
  APPEND VALUE #( mandt='*' txntype='HEDG' description='Hedge Roll'        sort_order=4 active=abap_true ) TO lt_txn.
  APPEND VALUE #( mandt='*' txntype='FEE'  description='Facility Fee'      sort_order=5 active=abap_true ) TO lt_txn.

  " Update client field to current client before insert
  LOOP AT lt_prod ASSIGNING FIELD-SYMBOL(<p>). <p>-mandt = sy-mandt. ENDLOOP.
  LOOP AT lt_txn  ASSIGNING FIELD-SYMBOL(<t>). <t>-mandt = sy-mandt. ENDLOOP.

  DATA: lv_inserted TYPE i VALUE 0.

  " Use INSERT (not MODIFY) with ACCEPTING DUPLICATE KEYS for idempotency
  INSERT ztecb_prod_type FROM TABLE lt_prod ACCEPTING DUPLICATE KEYS.
  lv_inserted = lv_inserted + sy-dbcnt.
  INSERT ztecb_txn_type  FROM TABLE lt_txn  ACCEPTING DUPLICATE KEYS.
  lv_inserted = lv_inserted + sy-dbcnt.

  IF lv_inserted > 0.
    ls_result-status  = 'OK'.
    ls_result-message = lv_inserted && ' customising row(s) inserted'.
  ELSE.
    ls_result-status  = 'SKIP'.
    ls_result-message = 'All customising entries already exist'.
  ENDIF.

  APPEND ls_result TO gt_results.
  PERFORM log_step USING ls_result.
ENDFORM.

*======================================================================*
*  HELPERS
*======================================================================*
FORM log_step USING is_result TYPE ty_step_result.
  DATA(lv_icon) = SWITCH string(
    is_result-status
    WHEN 'OK'    THEN '✔'
    WHEN 'SKIP'  THEN '⊘'
    WHEN 'WARN'  THEN '⚠'
    WHEN 'ERROR' THEN '✘'
    ELSE              '?' ).

  WRITE: / lv_icon,
           '[Step', is_result-step, ']',
           is_result-name COLOR COL_KEY,
           '→', is_result-status COLOR COL_POSITIVE,
           ':',  is_result-message.
ENDFORM.

FORM display_summary.
  DATA: lv_ok    TYPE i,
        lv_skip  TYPE i,
        lv_warn  TYPE i,
        lv_error TYPE i.

  LOOP AT gt_results INTO DATA(ls).
    CASE ls-status.
      WHEN 'OK'.    lv_ok    = lv_ok    + 1.
      WHEN 'SKIP'.  lv_skip  = lv_skip  + 1.
      WHEN 'WARN'.  lv_warn  = lv_warn  + 1.
      WHEN 'ERROR'. lv_error = lv_error + 1.
    ENDCASE.
  ENDLOOP.

  WRITE: /.
  WRITE: / '═══════════════════════════════════════════════════════════'.
  WRITE: / ' SETUP SUMMARY'.
  WRITE: / '═══════════════════════════════════════════════════════════'.
  WRITE: / '  ✔ Completed :', lv_ok.
  WRITE: / '  ⊘ Skipped   :', lv_skip, '(already existed)'.
  WRITE: / '  ⚠ Warnings  :', lv_warn.
  WRITE: / '  ✘ Errors    :', lv_error.
  WRITE: /.

  IF lv_error > 0.
    WRITE: / 'ACTION REQUIRED: Fix errors above before proceeding.' COLOR COL_NEGATIVE.
  ELSEIF lv_warn > 0.
    WRITE: / 'WARNINGS exist — check items above and complete manual steps.' COLOR COL_TOTAL.
  ELSE.
    WRITE: / 'ALL STEPS COMPLETED SUCCESSFULLY.' COLOR COL_POSITIVE.
    WRITE: /.
    WRITE: / 'NEXT MANUAL STEPS:'.
    WRITE: / '  1. SE11  → Activate ZECB_LOAN_HDR table (deploy via abapGit)'.
    WRITE: / '  2. SEGW  → Generate MPC/DPC classes for ZCO_ECB_LOAN project'.
    WRITE: / '  3. SE41  → Create GUI status MAIN for Z_ECB_LOAN_VIEWER'.
    WRITE: / '  4. SE51  → Create screen 0100 with AREA1 custom control'.
    WRITE: / '  5. SE93  → Create transaction Z_ECB_LOAN for Z_ECB_LOAN_VIEWER'.
    WRITE: / '  6. Test  → Run Z_ECB_LOAN_VIEWER — enter Co Code and execute'.
  ENDIF.
  WRITE: / '═══════════════════════════════════════════════════════════'.
ENDFORM.

*----------------------------------------------------------------------*
*  Text elements
*----------------------------------------------------------------------*
*  TEXT-001 = 'Setup Options'
*  TEXT-002 = 'Steps to Execute'
