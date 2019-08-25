LIBNAME CR "/home/u37556198/ECRB94/data";

DATA cleaned_tourism;
	LENGTH country_name $ 50 
	       tourism_type $ 50
	       category $ 50;
	SET cr.tourism;
	RETAIN country_name tourism_type;
	IF a NE . THEN country_name=country;
	ELSE IF country IN ('Inbound tourism', 'Outbound tourism') 
		THEN tourism_type=country;
	ELSE DO;
		IF country='Arrivals - Thousands' 
			THEN category='Arrivals';
		ELSE IF country='Departures - Thousands' 
			THEN category='Departures';
		ELSE category=substr(country, 1, 
							 length(country) - length(scan(country, -1, " ")) - 1);
		category=STRIP(category);
		IF series=".." THEN series=" ";
		ELSE series=UPCASE(series);
		IF _2014=".." THEN y2014=.;
		ELSE y2014=INPUT(_2014, 8.);
		IF category IN ('Arrivals', 'Departures') THEN y2014 = y2014*1000;
		ELSE y2014=y2014*1000000;
		OUTPUT;
	END;
	FORMAT y2014 COMMA16.;
	KEEP country_name tourism_type category series y2014;
RUN;

PROC SORT DATA=cleaned_tourism;
	BY country_name;
RUN;

PROC FORMAT;
	VALUE CONTINENTFMT 1='North America'
	                   2='South America'
	                   3='Europe'
	                   4='Africa'
	                   5='Asia'
	                   6='Oceania'
	                   7='Antartica'
	                   OTHER='Unknown';
RUN;

DATA country_info;
	SET cr.country_info(RENAME=(continent=continentNumeric));
	LENGTH country_name $ 50
	       continent $ 20;
	country_name=country;
	continent=STRIP(PUT(continentNumeric, CONTINENTFMT.));
	KEEP country_name continent;
RUN;

PROC SORT DATA=country_info;
	BY country_name;
RUN;

DATA final_tourism 
     noCountryFound(KEEP=country_name);
	MERGE cleaned_tourism(IN=a) 
	      country_info(IN=b);
	BY country_name;
	IF a AND b THEN OUTPUT final_tourism;
	ELSE IF a AND first.country_name THEN OUTPUT noCountryFound;
RUN;

PROC SORT DATA=final_tourism;
	BY continent;
RUN;

PROC MEANS DATA=final_tourism MEAN MIN MAX MAXDEC=0;
	VAR y2014;
	CLASS continent;
RUN;

PROC SQL;
	CREATE TABLE mean_expenditures AS
	SELECT ROUND(MEAN(y2014), 1)
	FROM final_tourism
	WHERE category='Tourism expenditure in other countries - US$';
QUIT;
