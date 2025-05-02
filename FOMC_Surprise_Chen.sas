**************************************************************************************;
* Last Update: Feb 2025                                                              *;
*                                                                                    *; 
* This SAS code estimate the FOMC surprise using same method as Chen (2020).         *;
* We can change the estimate window used in the code.                                *;
* By using announcement_Chen.csv as our announcement data and [-60, 5] window,       *; 
* we can reproduce the estimate results in Chen (2020).                              *;  
* Note that the announcement dates we collected are a bit different from Chen (2020) *;
**************************************************************************************;

************************************************************;
* Part 1 - Import fed funds futures data (1995-2024)       *;   
************************************************************;
*
* Calculate adjusted_price and implied rates by using T.price variable;
* Delete unreasonable data and data with price greater than 90;

proc import datafile="C:\Users\¤ý«FÒj\Desktop\RA\Kim\data.csv"
	out=ff1
	dbms=csv
	replace;
	getnames=yes;
run;

data ff1;
	set ff1(drop= Sequence 'Session Ind'n Symbol 'C/P/F'n 'A/B'n IND 'C/O'n
			MKQ VOE PC CAN INS CAB BKI 'F/L'n); *drop some useless columns;
	Datetime = Datetime + 3600; *adjustment from central time to Eastern time;
	format Datetime datetime18.;
run;

data ff1;
	set ff1;
	
	if T.price >= 1000000 then adjusted_price = T.price/100000;
	else if T.price >= 100000 then adjusted_price = T.price/10000;
	else if T.price >= 10000 then adjusted_price = T.price/1000;
	else if T.price >= 1000 then adjusted_price = T.price/100;
	else if T.price >= 100 then adjusted_price = T.price/10;
	else adjusted_price=T.price;

	if T.Date = 20011106 and adjusted_price = 99.79 then delete; *follow Chen (2020);

	implied_rate = (100 - adjusted_price) / 100;
run; 

data ff1;
	set ff1;
	if adjusted_price >= 90; 
run; 

**************************************************************************************;
* Part 2 - Create two data 'ff1_current' and 'ff1_next' to seperate the current month*;
* contract and next month contract.                                                  *;    
**************************************************************************************;
*
* In this part, we recognize when a contract expire using the Contract_Delivery variable.
* For example, the contracts with Contract_Delivery=9503 expire at the end of 1995/3, and
* the contracts with Contract_Delivery=212 expire at the end of 2002/12.;

data ff1_current;
	set ff1(rename=('Contract Delivery'n=Contract_Delivery));
	formatted_date = input(put(T.Date, 8.), yymmdd8.);
	format formatted_date date9.;
	year_of_trade = year(formatted_date);
	month_of_trade = month(formatted_date);

	contract_year = input(substr(put(Contract_Delivery, z4.), 1, 2), 4.);
	contract_month = input(substr(put(Contract_Delivery, z4.), 3, 2), 2.);

	if contract_year < 50 then full_contract_year = 2000 + contract_year;
	else full_contract_year = 1900 + contract_year;

	if year_of_trade = full_contract_year and month_of_trade = contract_month then output;
run;

data ff1_next;
	set ff1(rename=('Contract Delivery'n=Contract_Delivery));
	formatted_date = input(put(T.Date, 8.), yymmdd8.);
	format formatted_date date9.;
	year_of_trade = year(formatted_date);
	month_of_trade = month(formatted_date);

	next_month = intnx('month', formatted_date, 1); 
    format next_month date9.; 
	year_of_next_month = year(next_month);
	month_of_next_month = month(next_month);

	contract_year = input(substr(put(Contract_Delivery, z4.), 1, 2), 4.);
	contract_month = input(substr(put(Contract_Delivery, z4.), 3, 2), 2.);

	if contract_year < 50 then full_contract_year = 2000 + contract_year;
	else full_contract_year = 1900 + contract_year;

	if full_contract_year = year_of_next_month and contract_month = month_of_next_month then output;
run;

*******************************************************;
* Part 3 - Import announcement data we collected      *;                                                          
*******************************************************;
*
* In this part, we import announcement.csv, which contains the FOMC release time
* we collected from FED website, Bloomberg, and Datastream. We can also use
* announcement_Chen.csv to reproduce the estimation results in Chen (2020).;

proc import datafile="C:\Users\¤ý«FÒj\Desktop\RA\Kim\announcement.csv"
	out=announcements
	dbms=csv 
	replace;
	getnames=yes;
run;

data announcements;
	set announcements;
	format Datetime datetime18.;
run;

***************************************************************;
* Part 4 - Select the quote data in the window specified      *;                                                          
***************************************************************;
*
* In this part, we specify a estimate window (e.g. [-15, 45]), and select the
* quote data in this window. For the data in [t, t-£Gt], we store them in 
* data 'ff1_before', for those in [t, t+£Gt], we store them in data 'ff1_after'.
* Note that if the announcement date is in the last 7 days or that month, then
* we will use next month contract instead of current month contract.;

data ff1_before ff1_after;

	if 0 then set ff1_current nobs=n_current;
    if 0 then set ff1_next nobs=n_next;
    
	do until(eof_announcements);
		set announcements(rename=(Datetime=announcement_time)) end=eof_announcements;

		last_day_of_month = intnx('month', Date, 0, 'end');
		format last_day_of_month date9.;
		
		if last_day_of_month - Date > 7 then do;
			do p=1 to n_current;
				set ff1_current(rename=(Datetime=Datetime_current)) point=p;
				dt = Datetime_current;
				format dt datetime18.;

		        if dt >= intnx('second', announcement_time, -600) and dt < announcement_time then do;
		            output ff1_before;
		        end;
		        
		        else if dt >= announcement_time and dt <= intnx('second', announcement_time, 1200) then do;
		            output ff1_after;
		        end;
		    end;
		end;
		else do;
			do p=1 to n_next;
				set ff1_next(rename=(Datetime=Datetime_next)) point=p;
				dt = Datetime_next;
				format dt datetime18.;

		        if dt >= intnx('second', announcement_time, -600) and dt < announcement_time then do;
		            output ff1_before;
		        end;
		        
		        else if dt >= announcement_time and dt <= intnx('second', announcement_time, 1200) then do;
		            output ff1_after;
		        end;
		    end;
		end;
	end;
run;

**********************************************************************************;
* Part 5 - Calculate average implied rate before and after the announcement      *;                                                          
**********************************************************************************;
*
* In this part, we calculate the average implied rate before and after the announcement
* by using ff1_before and ff1_after we created in part 4. Note that the average implied
* rate is calculated using the "unique" quote in the period. For example, if the quote
* in [t, t-£Gt] is (0.02 0.03 0.02 0.04), the average implied rate is calculated using
* (0.02 + 0.03 + 0.04) / 3;

proc sql;
	create table avg_before as 
	select 
		announcement_time,
		mean(distinct implied_rate) as avg_implied_rate_before
	from ff1_before group by announcement_time;

	create table avg_after as 
	select
		announcement_time,
		mean(distinct implied_rate) as avg_implied_rate_after 
	from ff1_after group by announcement_time;

	*merge two table;
	create table avg_implied_rates as 
	select 
		a.announcement_time,  
		a.avg_implied_rate_before, 
		b.avg_implied_rate_after 
	from avg_before as a left join avg_after as b 
	on a.announcement_time = b.announcement_time;
quit;

*************************************************************;
* Part 6 - Estimate the monetary shock (FOMC surprise)      *;                                                          
*************************************************************;
*
* In this part, we calculate the scaling factor as D / (D - d), where D is the day
* in that month, and d is the day passed. For example, the scaling factor for
* 2012/3/4 is 31 / (31 - 3). If the date is in the last 7 days of that month, then
* the scaling factor is simply set equals to 1.
* As long as we have scaling factor (SF), we can calculate monetary shock using
* SF * (avg_implied_rate_after - avg_implied_rate_before);

proc sql; 
	create table monetary_shock as 
	select 
		announcement_time,
		input(put(datepart(announcement_time), date9.), date9.) as announcement_date,
		put(datepart(announcement_time), yymmdd10.) as format_date,
		day(intnx('month', calculated announcement_date, 0, 'end'))as total_days,
		day(calculated announcement_date) as days_passed,
		case	
			when intnx('month', calculated announcement_date, 0, 'end')-calculated announcement_date>7 then
				calculated total_days / (calculated total_days - (calculated days_passed-1))
			else 1
		end as adjust,

		calculated adjust * (avg_implied_rate_after - avg_implied_rate_before) as shock
	from avg_implied_rates;
quit;

***********************************************;
* Part 7 - Export the estimation results      *;                                                          
***********************************************;
*
* Remember to change the pdf file name when using different windows for estimation;

data export_data;
	set monetary_shock (keep=announcement_time format_date shock);
run;

proc export data=export_data
    outfile="C:\Users\¤ý«FÒj\Desktop\RA\Kim\Results\FOMC_surprise_Chen_tight.csv"
    dbms=csv
    replace;
    putnames=yes;
run;

/*
ods pdf file="C:\Users\¤ý«FÒj\Desktop\RA\Kim\Results\Complete_FOMC_surprise_wide.pdf";

proc print data = announcements;
run;

proc print data = avg_implied_rates;
run;

proc print data =  monetary_shock;
run;

ods pdf close;
*/