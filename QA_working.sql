--1)	Genera Statistics
--	a.	Total # of customers: Pirority groups


select *, sum(cust_cnt)over(order by priority_custs) as cumulative_cust from
(select priority_custs,cust_category,count(distinct cust_acct_key) as cust_cnt 
from final_offer_assgmt_window_dm1 group by 1,2 order by priority_custs)a 
order by priority_custs;

--	b.	Total # of offers, rebates, estimated costs

select *, total_rebate*resp_rate as cost_redemption from
(select priority_custs,cust_category,type,
case when type='vendor' then 0 
when type='product' then 0.65 
when type='ofb' then 0.65 else 1 end as resp_rate,
count(distinct cust_acct_key) as custs,
sum(offers) as offers,
sum(rebate) as total_rebate
from
(select priority_custs,cust_category,cust_acct_key,type,count(distinct precima_ofb_id) as offers,sum(inc_bound_final) as rebate  
from 
final_offer_assgmt_window_dm1 
group by 1,2,3,4) a
group by 1,2,3,4)a order by 1,3
;

--	c.	Offer distribution by vendor WRT vendor budget restraint
select b.brandname,a.* from 
(select a.*,b.rounded_budget as offer_limit
from
(select precimavendorid,precimaofferid,count(distinct cust_acct_key) as offer_count 
from 
final_offer_assgmt_window_dm1 
where type='vendor'
group by 1,2) a
left join
(select precimavendorid,precimaofferid,rounded_budget from :final_vendor_offer_table where offer_class='Vendor' group by 1,2,3 order by 1,2) b
on a.precimavendorid=b.precimavendorid
and a.precimaofferid=b.precimaofferid
order by 1,2)a
left join
mor_vmps_offer_hist b
on a.precimaofferid =b.precimaofferid

--	d.	Offer distribution by product
select a.*, b.offercopy 
from
(select precimaofferid, count(*) as offer_cnt
from 
final_offer_assgmt_window_dm1 
where type='product'
group by 1)a
left join
mor_vmps_offer_hist b
on
a.precimaofferid=b.precimaofferid
(select mpc, min(prod_desc) as prod_desc from :product_table group by 1)b
on a.mpc=b.mpc;

--	e.	Offer distribution by offer bank
select a.precima_ofb_id,b.offer_bank_name,a.offer_cnt from
(select 'MOR-'||item1 as precima_ofb_id, count(*) as offer_cnt
from 
final_offer_assgmt_window_dm1 
where type='ofb'
group by 1)a
left join
(select precima_ofb_id, offer_bank_name from nz.MSN_campaign_offer_Bank_hist group by 1,2) b b
on a.precima_ofb_id=b.precima_ofb_id
group by 1,2,3;

--2)	Business Rules
	--a.	Business Rules spreadsheet
		--i.	Product exclusions
			--1.	Tobacco/Lottery/Pharmacy/Baby Milk/Café/Gibraltar/Dry Cleaning & Photo Centre/Fuel/Fireworks/Standard Exclusions: Other/Standard exclusions: Waste and Markdowns/
			--2.	In offer bank table, all categories above have promoted_flag=’N’
			--3.	Only offer banks with promoted_flag in (‘X’, ‘Y’) and the latest effective_start_date are used

select 'MOR-'||item1 as precima_ofb_id from  offer_incentive_print_allocations_union_all where type='ofb'
except
select distinct precima_ofb_id from MSN_campaign_offer_Bank_hist where promoted_flag != 'N';

		--ii.	Conditional product exclusions
			--	1.	BWS offers are point based  --TBD

		--iii.	Customer exclusions
			--1.	DM1 and Email: check channel opt-in status – must be channel eligible

select distinct cust_acct_key from offer_incentive_print_allocations_union_all where mail_opt_in_ind=1
except
select distinct cust_acct_key from msn_member where mail_opt_in_ind=1;

			--2.	Removed deceased customers (need confirmation: jeff mentioned even deceased ones can receive coupons)

select distinct cust_acct_key from offer_incentive_print_allocations_union_all
except
select distinct cust_acct_key from msn_member where deceased_flag=0; --there are deceased customers in our offer assgmt



		--iv.	Channel
			--1.	No duplicated offers within the same channel
			--2.	No duplicated offers within the same timeframe across channels (not needed right now if we only have DM1 result)
	--b.	Channel Brief(DM1)
		--i.	Max of 4 vendor offers
		--ii.	Max of 1 product offer
		--iii.	8 offers per customer
select mail_eligible,ofb_offers,vendor_offers,product_offers,(ofb_offers+vendor_offers+product_offers) as total_offers,count(distinct cust_acct_key) as custs
from
(select cust_acct_key,mail_eligible, 
sum(case when type='ofb' then offers else 0 end) as ofb_offers,
sum(case when type='vendor' then offers else 0 end) as vendor_offers,
sum(case when type='product' then offers else 0 end) as product_offers
from
(select cust_acct_key,case when mail_opt_in_ind=0 then 'N' else 'Y' end as mail_eligible,type,count(distinct precima_ofb_id) as offers
from
offer_incentive_print_allocations_union_all
group by 1,2,3) a
group by 1,2) a
group by 1,2,3,4
order by 1,2,3,4;
/*

mail_eligible	ofb_offers	vendor_offers	product_offers	total_offers	  custs
N					3				4				1				8			10
N					4				3				1				8			490
N					5				2				1				8			13156
N					5				3				0				8			2
N					6				1				1				8			149522
N					6				2				0				8			121
N					7				0				1				8			827283
N					7				1				0				8			2925
N					8				0				0				8			68649
Y					3				4				1				8			27
Y					4				3				1				8			1448
Y					5				2				1				8			41743
Y					5				3				0				8			7
Y					6				1				1				8			500123
Y					6				2				0				8			460
Y					7				0				1				8			2822415
Y					7				1				0				8			11356
Y					8				0				0				8			249811
*/

		--iv.	Window slots allocation  --TBD

	--c.	Super Groups
		--i.	One offer per offer bank per customer
		--ii.	No more than 20% offers from the same group
		--iii.	No more than 33% offers from the same super group
select mail_eligible,offer_banks_should_be_8,group_code_should_be_8,super_group_code_could_be_4_to_8,count(distinct cust_acct_key) as custs
from
(select case when mail_opt_in_ind=0 then 'N' else 'Y' end as mail_eligible,cust_acct_key,count(distinct precima_ofb_id) as offer_banks_should_be_8,count(distinct offer_bank_group_code) as group_code_should_be_8,
count(distinct offer_bank_supergroup_code) as super_group_code_could_be_4_to_8
from
offer_incentive_print_allocations_union_all
group by 1,2) a
group by 1,2,3,4
order by 1,2,3,4;

/*
mail_eligible	offer_banks_should_be_8	group_code_should_be_8	super_group_code_could_be_4_to_8		custs
N					8							8							4								 5,965
N					8							8							5								672,042
N					8							8							6								370,921
N					8							8							7								 13,230
Y					8							8							4								 17,788
Y					8							8							5								2,269,846
Y					8							8							6								1,290,935
Y					8							8							7								 48,821
*/

d.	Incentive level
i.	Within max and min range
ii.	Correct incentive type: points v.s. pounds
iii.	Correct incremental
e.	Budget
i.	Morrison total budget restraint
ii.	Vendor budget restraint
