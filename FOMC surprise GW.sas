**************************************************************************************;
* Last Update: Feb 2025                                                              *;
*                                                                                    *; 
* This SAS code estimate the FOMC surprise using same method as GW (2016) from 1995  *;
* to 2016. The windows used for estimation are [-10,20] and [-15,45] and the results *; 
* are rounded to the fifth decimal place.											 *; 
*																					 *;
* Current problem: The calculation of FOMC surprise involves volume, but before 2004 *;																				
* all the volume equal to 0, which seems strange. However, for the estimation after  *;
* 2004, there are non-zero volume for each date and the estimation results are quite *;
* similar with GW (2016).															 *; 	
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
	set ff1(drop= 'Session Ind'n Symbol 'C/P/F'n 'A/B'n IND 'C/O'n
			MKQ VOE PC CAN INS CAB BKI 'F/L'n); *drop some useless columns;
	Datetime = Datetime + 3600; *adjustment from central time to Eastern time;
	format Datetime datetime18.;
	*/GW'S results are from 1995-2016, we extend the estimation to 2024*/
	*if Datetime <= '31DEC2009:23:59:59'dt; 
run;

data ff1;
	set ff1;
	
	if T.price >= 1000000 then adjusted_price = T.price/100000;
	else if T.price >= 100000 then adjusted_price = T.price/10000;
	else if T.price >= 10000 then adjusted_price = T.price/1000;
	else if T.price >= 1000 then adjusted_price = T.price/100;
	else if T.price >= 100 then adjusted_price = T.price/10;
	else adjusted_price=T.price;

	if T.Date = 20011106 and adjusted_price = 99.79 then delete;

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
* In this part, we import announcement.csv, which contains the FOMC release time.
* We simply use the announcement dates from 1995-2009 from GW (2016).;

proc import datafile="C:\Users\¤ý«FÒj\Desktop\RA\Kim\announcement.csv"
	out=announcements
	dbms=csv 
	replace;
	getnames=yes;
run;

data announcements;
	set announcements;
	format Datetime datetime18.;
	*if Datetime <= '31DEC2009:23:59:59'dt;

	last_day_of_month = intnx('month', datepart(Datetime), 0, 'end');
	last_7_days_start = intnx('day', last_day_of_month, -6); 
	if datepart(Datetime) >= last_7_days_start then use_next = 1;
	else use_next = 0;

	drop last_day_of_month last_7_days_start;
run;

***************************************************************;
* Part 4 - Select the quote data in the beginning and the end *;
* of the windoe specified.                                    *;                                                                                      
***************************************************************;
*
* In this part, we specify a estimate window (e.g. [-10, 20]), and select the
* quote data at the beginning and the end of this window. In GW (2016), they mention
* that they calculate FOMC surprise using the fed funds futures rate shortly after
* t and the fed funds futures rate just before t, but say nothing about the detail
* about how the rate is selected. Thus, we refer to GSS (2005). According to GSS (2005),
* when there is no federal funds futures trade exactly at the beginning of the
* specified window, we use the most recent price (vol¡Ú0). When there is no trade exactly
* at the end of the specified window, we use the next available trade price (vol¡Ú0). Base
* on this description, we select the last trade price (vol¡Ú0) before time t-£Gt as rate
* before, and select the first trade price (vol¡Ú0) after time t+£Gt as the rate after. If
* there are no qualified trade (all vol=0), then we simply use the last quote before time
* t-£Gt as rate before and the first quote after time t+£Gt as rate after.
*
* To make it more concrete, here's an example of how I select the rate before announcement
* and rate after announcement using 20040504 data, where the announcement time on that
* day is 14:15 and the window specified is [-10,20]: 
*
* Time     Rate    Volume
* 13:55:07 0.0103  6
* 14:04:46 0.01025 0
* 14:05:56 0.0103  0
*          .
*          .
*		   .
* 14:14:54 0.0102  2
* 14:16:41 0.0102  8
*          .
*          .
*          .
* 14:34:09 0.0102  236
* 14:35:04 0.0102  1
*
* In this example, although the last quote before 14:05 is 0.01025, we will still use the quote at 13:55:07
* for before_rate because the quote at 14:04:46 has a 0 volume. And for after_rate, we can use the first quote
* after 14:35 (i.e. 0.0102) directly since it volume=1.
*
* Note that if the announcement date is in the last 7 days or that month, then
* we will use next month contract instead of current month contract.;

data before_trade;
    set announcements(keep=Datetime use_next); 
    format implied_rate_before 8.6;

    announcement_time = Datetime; 

    /* Initialize */
    last_trade_time = .;
    last_trade_rate = .;
    backup_trade_time = .;
    backup_trade_rate = .;

    /* Select the data used according to var 'use_next' */
    if use_next = 0 then do i = 1 to nobs_current;
        set ff1_current point=i nobs=nobs_current; 

        /* First, try to find the last trade (Volume > 0) before t-£Gt */
        if Datetime <= intnx('second', announcement_time, -900) 
           and datepart(Datetime) = datepart(announcement_time) then do; 
            if Volume > 0 then do;
                if missing(last_trade_time) or Datetime > last_trade_time then do;
                    last_trade_time = Datetime;
                    last_trade_rate = implied_rate;
                end;
            end;

            /* Store the last trade (even if Volume = 0) as a backup */
            if missing(backup_trade_time) or Datetime > backup_trade_time then do;
                backup_trade_time = Datetime;
                backup_trade_rate = implied_rate;
            end;
        end;
    end;
    else do i = 1 to nobs_next;
        set ff1_next point=i nobs=nobs_next; 

        /* First, try to find the last trade (Volume > 0) before t-£Gt */
        if Datetime <= intnx('second', announcement_time, -900) 
           and datepart(Datetime) = datepart(announcement_time) then do; 
            if Volume > 0 then do;
                if missing(last_trade_time) or Datetime > last_trade_time then do;
                    last_trade_time = Datetime;
                    last_trade_rate = implied_rate;
                end;
            end;

            /* Store the last trade (even if Volume = 0) as a backup */
            if missing(backup_trade_time) or Datetime > backup_trade_time then do;
                backup_trade_time = Datetime;
                backup_trade_rate = implied_rate;
            end;
        end;
    end;

    /* If no trade with Volume > 0 is found, use the last available trade */
    if missing(last_trade_rate) then last_trade_rate = backup_trade_rate;

    implied_rate_before = last_trade_rate;
    keep announcement_time use_next implied_rate_before;
    format announcement_time datetime18.;

    /* Only output valid results */
    if not missing(implied_rate_before);
run;

data after_trade;
    set announcements(keep=Datetime use_next);
    format implied_rate_after 8.6;

    announcement_time = Datetime; 

    /* Initialize */
    first_trade_time = .;
    first_trade_rate = .;
    backup_trade_time = .;
    backup_trade_rate = .;

    /* Select the data used according to var 'use_next' */
    if use_next = 0 then do i = 1 to nobs_current;
        set ff1_current point=i nobs=nobs_current;

        /* First, try to find the first trade (Volume > 0) after t+£Gt */
        if Datetime >= intnx('second', announcement_time, 2700) 
           and datepart(Datetime) = datepart(announcement_time) then do; 
            if Volume > 0 then do;
                if missing(first_trade_time) then do;
                    first_trade_time = Datetime;
                    first_trade_rate = implied_rate;
                end;
            end;

            /* Store the first available quote as a backup */
            if missing(backup_trade_time) then do;
                backup_trade_time = Datetime;
                backup_trade_rate = implied_rate;
            end;
        end;
    end;
    else do i = 1 to nobs_next;
        set ff1_next point=i nobs=nobs_next;

        /* First, try to find the first trade (Volume > 0) after t+£Gt */
        if Datetime >= intnx('second', announcement_time, 2700) 
           and datepart(Datetime) = datepart(announcement_time) then do; 
            if Volume > 0 then do;
                if missing(first_trade_time) then do;
                    first_trade_time = Datetime;
                    first_trade_rate = implied_rate;
                end;
            end;

            /* Store the first available quote as a backup */
            if missing(backup_trade_time) then do;
                backup_trade_time = Datetime;
                backup_trade_rate = implied_rate;
            end;
        end;
    end;

    /* If no trade with Volume > 0 is found, use the first available quote */
    if missing(first_trade_rate) then first_trade_rate = backup_trade_rate;

    implied_rate_after = first_trade_rate;
    keep announcement_time use_next implied_rate_after;
    format announcement_time datetime18.;

    /* Only output valid results */
    if not missing(implied_rate_after);
run;


*****************************************************;
* Part 5 - Merge before_trade and after_trade       *;                                                          
*****************************************************;
proc sql;
	create table avg_implied_rates as 
	select 
		a.announcement_time,  
		a.use_next, 
		a.implied_rate_before, 
		b.implied_rate_after
	from before_trade as a 
	left join after_trade as b 
	on a.announcement_time = b.announcement_time;
quit;

***********************************************************************;
* Part 6 - Estimate Monetary Shock, following GSS(2005)               *;
***********************************************************************;
proc sql; 
	create table monetary_shock as 
	select 
		announcement_time,
		input(put(datepart(announcement_time), date9.), date9.) as announcement_date,
		put(datepart(announcement_time), yymmdd10.) as format_date,
		day(intnx('month', datepart(announcement_time), 0, 'end')) as total_days, /*total days in that month*/
		day(datepart(announcement_time)) as days_passed, /*day passed (e.g. the day passed for 2/10 is 10)*/
		case	
			when use_next = 1 then 1 /*if use_next=1 then scaling term=1*/
			else calculated total_days / (calculated total_days - calculated days_passed)
		end as adjust,
		round(calculated adjust * (implied_rate_after - implied_rate_before), 0.00001) as shock
	from avg_implied_rates;
quit;

***********************************************************************;
* Part 7 - Export the estimation results in csv file                  *;
***********************************************************************;
data export_data;
	set monetary_shock (keep=announcement_time format_date shock);
run;

proc export data=export_data
    outfile="C:\Users\¤ý«FÒj\Desktop\RA\Kim\Results\FOMC_surprise_GW_wide.csv"
    dbms=csv
    replace;
    putnames=yes;
run;

*/
ods pdf file="C:\Users\¤ý«FÒj\Desktop\RA\Kim\Results\FOMC_surprise_GW_wide.pdf"

title "Monetary Shock Estimation Results"
proc print data=monetary_shock noobs label
run

ods pdf close;
*/ 
