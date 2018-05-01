libname sassymp 'E:\MBAN\SAS Symposium';
data sassymp.predictbolast; 
	
	infile "E:\MBAN\SAS Symposium\Training_Dataset.csv" dsd missover;
	input sku national_inv lead_time in_transit_qty	forecast_3_month 
		forecast_6_month forecast_9_month sales_1_month sales_3_month 
		sales_6_month sales_9_month min_bank potential_issue $ pieces_past_due	
		perf_6_month_avg perf_12_month_avg local_bo_qty deck oe	
	 ppap auto_buy $ rev $ backorder $;
	if perf_6_month_avg="-99" then perf_6_month_avg=_;
    if perf_12_month_avg="-99" then perf_12_month_avg=_;
	if backorder = 'Yes' then went_on_backorder = 1;
	else went_on_backorder = 0;
	if deck = 'No' then deck_risk = 0.0;
	else deck_risk = 1.0;
	if oe= 'No' then oe_constraint = 0.0;
	else oe_constraint = 1.0;
	if ppap = 'No' then ppap_risk = 0.0;
	else ppap_risk = 1.0;
	if auto_buy = 'No' then stop_auto_buy = 0.0;
	else stop_auto_buy = 1.0;
    
run;

options nodate nonumber;


%macro missing_indicators(dsn=,exclude=,out=);
	proc means data=&dsn(drop=&exclude) noprint;
		var _numeric_;
		output nmiss= out=temp(drop=_type_ _freq_);
	run;
	proc transpose data=temp out=temp;
	run;
	proc sql noprint;
		select _name_ into :missing separated by " "
			from temp where col1 > 0;
	quit;
	data _null_;
		call symputx('nmissing',length("%cmpres(&missing)")-
			length(compress("%cmpres(&missing)"))+1);
	run;
	data &out;
		set &dsn;
		%do i=1 %to &nmissing;
			%let variable=%scan(&missing,&i);
			M_&variable=(&variable=.);
		%end;
	run;
%mend missing_indicators;

/* ------------ training data ------------ */

/* get training data variable names  */
proc contents data=sassymp.predictbolast out=temp(keep=name type) noprint;
run;

/* create macro variable of numeric inputs */
proc sql noprint;
	select name into: interval separated by " "
	from temp
	where type=1;
quit;

title1 'Number of Training Data Missing Values (Pre-Imputation)';
proc means data=sassymp.predictbolast n nmiss;
	var &interval;
	output median= out=medians(drop=_type_ _freq_) / autoname;
run;

/* get median replacement value names */
proc contents data=medians out=temp(keep=name type) noprint;
run;

/* create macro variable of median input values */
proc sql noprint;
	select name into: med separated by " "
	from temp
	where type=1;
quit;

%missing_indicators(dsn=sassymp.predictbolast,exclude=ins,out=sassymp.predictbolast_imputed)

/* replace missing values with medians */
data sassymp.predictbolast_imputed(drop=i &med);
	if _n_= 1 then set medians;
	set sassymp.predictbolast_imputed;
	array x{*} &interval;
	array y{*} &med;
	do i=1 to dim(x);
		if x{i}=. then x{i}=y{i};
	end;
run;

title1 'Training Data Missing Values (Post-Imputation)';
proc means data=sassymp.predictbolast_imputed n nmiss;
	var &interval;
run;

proc print data = sassymp.predictbolast_imputed (obs=1000);
run;

proc corr data = sassymp.predictbolast_imputed;
run;

proc means data = sassymp.predictbolast_imputed;
	class went_on_backorder;
run;

%let remaining = national_inv lead_time in_transit_qty	forecast_9_month sales_3_month 
		min_bank pieces_past_due local_bo_qty deck_risk oe_constraint ppap_risk stop_auto_buy;
title1 'Determine P-Value for Entry and Retention';

proc sql;
	select 1 - probchi(log(sum(went_on_backorder ge 0)),1) into :sl
	from sassymp.predictbolast_imputed;
quit;

proc sort data=sassymp.predictbolast_imputed out=develop;
	by went_on_backorder;
run;

proc surveyselect data=develop method = srs rate = (50,50) seed=4444 out=sample;
		strata went_on_backorder;
run;

proc logistic data=sample;
	model went_on_backorder(event='1')= &remaining 
	/*	national_inv | lead_time| in_transit_qty |forecast_9_month |sales_3_month| 
		min_bank |pieces_past_due |local_bo_qty |deck_risk |oe_constraint |
		ppap_risk| stop_auto_buy @2 */ / include = 30 clodds = pl selection = forward slentry=&sl;
run;
