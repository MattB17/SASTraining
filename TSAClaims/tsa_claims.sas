/***************************************************
* IMPORTING THE DATA;
***************************************************/
%LET dataFolder=/home/u37556198/ECRB94/data;
%LET dataName=TSAClaims2002_2017.csv;
%LET outpath=/home/u37556198/ECRB94/output;

LIBNAME tsa "&dataFolder";

* so that column names follow SAS naming conventions;
OPTIONS VALIDVARNAME=v7;

PROC IMPORT DATAFILE="&dataFolder/&dataName"
            DBMS=csv
            OUT=tsa.tsa_claims_raw
            REPLACE;
	GUESSINGROWS=MAX;
RUN;

/***************************************************
* EXAMINING DATA
***************************************************/

* generating a report of the data set's contents;
PROC CONTENTS DATA=tsa.tsa_claims_raw;
RUN;

* checking the contents of claim_type, claim_site, and disposition;
* which can only have a prescribed set of values;
PROC FREQ DATA=tsa.tsa_claims_raw;
	TABLES claim_type claim_site disposition / NOCUM;
RUN;

* looking at cross of state and stateName, this should be a 1 to 1 mapping;
PROC FREQ DATA=tsa.tsa_claims_raw;
	TABLES state*stateName / NOROW NOCOL;
RUN;

* looking at the date numeric column for close amount;
PROC UNIVARIATE DATA=tsa.tsa_claims_raw;
	VAR close_amount;
RUN;

* looking at summaries for dates;
PROC TABULATE DATA=tsa.tsa_claims_raw;
	VAR incident_date date_received;
	TABLE incident_date date_received,
	      N NMISS (MIN MAX MEDIAN MEAN)*F=YEAR4. RANGE;
RUN;

* a quick look at date values that do not make sense;
%LET missing_date_condition=(incident_date=.) OR (date_received=.);
%LET out_of_range_condition=(YEAR(incident_date) < 2002) OR (YEAR(incident_date) > 2017) OR
                            (YEAR(date_received) < 2002) OR (YEAR(date_received) > 2017);
%LET invalid_dates_condition=incident_date > date_received;

DATA date_summary;
	SET tsa.tsa_claims_raw(KEEP=incident_date date_received);
	LENGTH row_description $ 20;
	IF &missing_date_condition. THEN row_description="Missing";
	ELSE IF &out_of_range_condition. THEN row_description="Out of Range";
	ELSE IF &invalid_dates_condition. THEN row_description="Invalid Dates";
	ELSE row_description="Clean";
RUN;

PROC FREQ DATA=date_summary;
	TABLES row_description;
RUN;

/***************************************************
 * DATA CLEANING
 *
 * If there is a "/" in claim_type then take claim type
 *    as the word before the "/"
 * There are two categories of disposition that are coded wrong
 * For claim_type, claim_site, and disposition - is
 *    recoded as unknown
 * stateName needs to be Proper Case
 * state needs to be upper case
 * identify date issues
***************************************************/
* remove entirely duplicated observations;
PROC SORT DATA=tsa.tsa_claims_raw OUT=tsa_no_duplicates NODUPRECS;
	BY _ALL_;
RUN;

DATA tsa_claims_clean;
	SET tsa.tsa_claims_raw;
	LENGTH date_issues $ 12;

	IF claim_type IN ("-", " ", "") THEN claim_type="Unknown";
	ELSE claim_type=TRIM(SCAN(claim_type, 1, "/"));

	IF claim_site IN ("-", " ", "") THEN claim_site="Unknown";
	ELSE claim_site=TRIM(claim_site);

	IF disposition="Closed: Canceled" THEN disposition="Closed:Canceled";
	ELSE IF disposition="losed: Contractor Claim" THEN disposition="Closed:ContractorClaim";
	ELSE IF disposition IN ("-", " ", "") THEN disposition="Unknown";
	ELSE disposition=TRIM(disposition);

	stateName=PROPCASE(stateName);
	state=UPCASE(state);

	IF (&missing_date_condition.) OR (&out_of_range_condition.)
	    OR (&invalid_dates_condition.) THEN date_issues="Needs Review";

	FORMAT close_amount DOLLAR12.2 incident_date date_received DATE9.;
	LABEL airport_code="Airport Code"
	      airport_name="Airport Name"
	      claim_number="Claim Number"
	      claim_site="Claim Site"
	      claim_type="Claim Type"
	      close_amount="Close Amount"
	      date_received="Date Received"
	      disposition="Disposition"
	      incident_date="Incident Date"
	      item_category="Item Category"
	      state="State"
	      stateName="State Name";
	DROP city county;
RUN;

PROC SORT DATA=tsa_claims_clean OUT=tsa.tsa_claims_clean;
	BY incident_date;
RUN;

* check that cleaning was done correctly;
PROC FREQ DATA=tsa.tsa_claims_clean ORDER=FREQ;
	TABLES claim_type claim_site disposition / NOCUM;
RUN;

* check the values for state, stateName, ad date_issues;
PROC FREQ DATA=tsa.tsa_claims_clean ORDER=FREQ;
	TABLES state stateName date_issues / NOCUM;
RUN;

* check the distribution of date_received and incident_date for the clean dates;
PROC TABULATE DATA=tsa.tsa_claims_clean;
	VAR incident_date date_received;
	TABLE incident_date date_received,
	      N NMISS (MIN MAX MEDIAN MEAN)*F=YEAR4. RANGE;
	WHERE date_issues NE "Needs Review";
RUN;

/****************************************************************
* ANALYSIS
*****************************************************************/

* splitting data into two datasets based on whether there is a date issue;
PROC SQL;
	CREATE TABLE tsa.date_issues AS
	SELECT *
	FROM tsa.tsa_claims_clean
	WHERE date_issues = "Needs Review";

	CREATE TABLE tsa.claims_date_clean AS
	SELECT *
	FROM tsa.tsa_claims_clean
	WHERE date_issues NE "Needs Review";
QUIT;

%LET analysis_state=HI;

* count of the number of date_issues;
* table for the state;
PROC SQL NOPRINT;
	CREATE TABLE date_issues_count AS
	SELECT "Claims With Date Issues" AS category LABEL=" ",
	        COUNT(*) AS count LABEL="Claims Count"
	FROM tsa.date_issues
	UNION ALL
	SELECT "Claims Without Date Issues" AS category LABEL=" ",
		COUNT(*) AS count LABEL="Claims Count"
	FROM tsa.claims_date_clean;

	CREATE TABLE tsa_&analysis_state._clean AS
	SELECT *
	FROM tsa.claims_date_clean
	WHERE state = "&analysis_state.";

	CREATE TABLE close_amount_summary AS
	SELECT MEAN(close_amount) AS mean LABEL="Mean Close Amount" FORMAT=DOLLAR12.,
	       MIN(close_amount) AS min LABEL="Minimum Close Amount" FORMAT=DOLLAR12.,
	       MAX(close_amount) AS max LABEL="Maximum Close Amount" FORMAT=DOLLAR12.,
	       SUM(close_amount) AS sum LABEL="Total Close Amount" FORMAT=DOLLAR12.
    FROM tsa_&analysis_state._clean;
QUIT;

ODS NOPROCTITLE;
ODS PDF FILE="&outpath/TSA_claims.pdf" PDFTOC=1 STYLE=sapphire;
ODS PROCLABEL "Count of Claims by Date Issues";
TITLE "Count of Claims by Date Issues";
PROC PRINT DATA=date_issues_count LABEL NOOBS;
	FORMAT count COMMA15.;
RUN;

ODS PROCLABEL "Claim Count by Year";
TITLE "Claims Without Date Issues";
TITLE2 "Claim Count by Year";
ODS GRAPHICS ON;
PROC FREQ DATA=tsa.claims_date_clean;
	TABLES incident_date / PLOTS=freqplot;
	FORMAT incident_date YEAR4.;
RUN;

ODS PROCLABEL "Claim Counts for &analysis_state.";
TITLE2 "Claim Counts for &analysis_state.";
PROC FREQ DATA=tsa_&analysis_state._clean;
	TABLES claim_type claim_site disposition / PLOTS=FREQPLOT(ORIENT=horizontal);
RUN;

ODS PROCLABEL "Summary Statistics for Close Amount in &analysis_state";
TITLE2 "Summary Statistics for Close Amount in &analysis_state";
PROC PRINT DATA=close_amount_summary LABEL NOOBS;
RUN;
TITLE;

ODS GRAPHICS OFF;
ODS PDF CLOSE;
