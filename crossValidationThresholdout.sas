/* Macro to separate train and test sets for K-fold cross-validation (CV) */
/* and a holdout set to assess the generalization error using the thresholdout algorithm */
/* The idea of a reusable holdout, it's implementation with the thresholdout algorithm and */
/* an explanation of what it means in adaptive data analysis can be found at the Google Research Blog article: */
/* https://research.googleblog.com/2015/08/the-reusable-holdout-preserving.html */

/* Original data is split randomly to K+1 folds */
/* and one of the folds (K+1) is reserved for thresholdout. */
/* Parameters: */
/* data= dataset to be analyzed */
/* cv_data= output with K-folds to be used in K-fold cross-validation */
/* tho_data= reusable holdout data for thresholdout algorithm */
/* K= number of folds in K-fold cross-validation */
/* rand_seed= seed for the random number generator */
%macro cv_thresho_sets(data=, cv_data=, tho_data=, K=, rand_seed=);

/* K+1 random folds */
data work.data_kplusone_folds;
set &data.;
uniform_random = ranuni(&rand_seed.);
do kfold = 1 to &K. + 1;
if (uniform_random > (1/(&K. + 1))*(kfold-1)) and (uniform_random <= (1/(&K. + 1))*kfold) then output;
end;
run;

/* Separate the data for K-fold CV and thresholdout */
/* K-fold CV, folds 1 to K */
data work.data_kfolds;
set work.data_kplusone_folds(where=(kfold ne &K. + 1));
run;

/* Thresholdout, fold K+1 */
data &tho_data.;
set work.data_kplusone_folds(where=(kfold = &K. + 1));
run;

/* Replicate the K-fold CV data K times */
proc surveyselect data=work.data_kfolds out=work.data_cvk_rep(drop=uniform_random Selected) seed=&rand_seed. samprate=1 outall reps=&K.;
run;

/* Form group variable for CV training and test sets */
data &cv_data.;
set work.data_cvk_rep;
if kfold ne Replicate then group = "train";
else group = "test";
run;

%mend cv_thresho_sets;

/* Here is a test run of the macro using sashelp data set junkmail and 5-fold cross-validation */
%cv_thresho_sets(data=sashelp.junkmail(drop=Test), cv_data=work.data_cvk_model, tho_data=work.data_thresho, K=5, rand_seed=1);



/* Let's identify our model as model 1 */
/* Using a model id will make it easier to use the macros in loops */
%let model_number = 1;

/* Macro for cross-validation */
/* Parameters: */
/* in_data= dataset to be used in K-fold cross-validation with K-folds (variable Replicate) divided to groups "train" and "test" */
/* e.g. cv_data from macro cv_thresho_sets */
/* y= output variable */
/* x= input variables */
/* model_id= identificator for the model y = x */
/* pred_path= path and filename for the code to predict y values in the CV phase */
/* final_path= path and filename for the code to predict y values using the whole data (without the holdout set) */
%macro cv_analysis(in_data=, y=, x=, model_id=, pred_path=, final_path=);

/* Train the model y = x on the training data */
/* Code for predicting the y values is saved to a file in pred_path */
proc genmod data=&in_data.(where=(group="train"));
model &y. = &x. / link=logit dist=binomial;
by Replicate;
code file="&pred_path.";
run;

/* The saved code is used to compute predictions on the training and test sets */
/* Training set prediction */
data work.train_set_pred;
set &in_data.(where=(group="train"));
%include "&pred_path.";
run;

/* Test set predictions */
data work.test_set_pred;
set &in_data.(where=(group="test"));
%include "&pred_path.";
run;

/* Calculate train errors, P_Class1 >= 0.5 -> predicted class = 1 */
data work.train_set_error;
set work.train_set_pred;
pred_class = round(P_Class1);
if &y. = pred_class then train_error = 0;
else train_error = 1;
run;

proc sort data=work.train_set_error;
by Replicate;
run;

/* Calculate training mean classification error for each K */
proc summary data=work.train_set_error;
var train_error;
by Replicate;
output out=work.cvk_train_err mean(train_error)=train_err;
run;

/* Calculate test errors, P_Class1 >= 0.5 -> predicted class = 1 */
data work.test_set_error;
set work.test_set_pred;
pred_class = round(P_Class1);
if &y. = pred_class then test_error = 0;
else test_error = 1;
run;

proc sort data=work.test_set_error;
by Replicate;
run;

/* Calculate test mean classification error for each K */
proc summary data=work.test_set_error;
var test_error;
by Replicate;
output out=work.cvk_test_err mean(test_error)=test_err;
run;

/* Combine train and test mean classification error values */
proc sql;
create table work.cvk_error as
select t1.Replicate, t1.train_err, t2.test_err
from work.cvk_train_err t1
left outer join
work.cvk_test_err t2
on t1.Replicate = t2.Replicate;
quit;

/* Calculate the CV test and train mean classification error for the model */
proc summary data=work.cvk_error;
var train_err test_err;
output out=work.cvk_mse_&model_id. mean(train_err)=train_mse mean(test_err)=test_mse;
run;

/* Final model y = x on whole data (without the holdout set) */
/* Code to make predictions is saved to a file final_path */
proc genmod data=&in_data.;
model &y. = &x. / link=logit dist=binomial;
code file="&final_path.";
run;

/* The saved code is used to compute predictions on the whole data (without the holdout set) */
data work.final_set_pred;
set &in_data.;
%include "&final_path.";
run;

/* Calculate final classification errors, P_Class1 >= 0.5 -> predicted class = 1 */
data work.final_set_error;
set work.final_set_pred;
pred_class = round(P_Class1);
if &y. = pred_class then final_error = 0;
else final_error = 1;
run;

/* Calculate final mean classification error */
proc summary data=work.final_set_error;
var final_error;
output out=work.cvk_final_mse_&model_id. mean(final_error)=final_mse;
run;

%mend cv_analysis;

%cv_analysis(in_data=work.data_cvk_model, y=Class, x=Data Direct Dollar, model_id=&model_number., pred_path=C:\codeSAS\myModels\genmod_model_pred_&model_number..sas, final_path=C:\codeSAS\myModels\genmod_model_final_&model_number..sas);



/* Let's make preparations for the thresholdout algorithm */

/* Count the number of observations in the holdout set */
%let dsid = %sysfunc(open(work.data_thresho,in));
%let nobs = %sysfunc(attrn(&dsid,nobs));

%macro close_data;
%if &dsid > 0 %then %let rc = %sysfunc(close(&dsid));
%mend close_data;

%close_data;

/* Set threshold and tolerance for the thresholdout algorithm */
/* Threshold */
%let th_val = %sysevalf(4.0/&nobs.); 
/* Tolerance */
%let tol_val = %sysevalf(1.0/&nobs.);

%put &th_val;

/* Macro for thresholdout algorithm */
/* Parameters: */
/* model_data= dataset containing the training mean classification error */
/* e.g. work.final_set_error produced by macro cv_analysis */
/* y= output variable */
/* thresho_data= the holdout data, e.g. tho_data from macro cv_thresho_sets */
/* model_path= path and filename for the code to predict y values in the holdout set */
/* threshold= threshold parameter for the thresholdout algorithm */
/* tolerance= tolerance parameter for the thresholdout algorithm */
/* rand_seed= seed for the random number generator */
%macro thresholdout(model_data=, y=, thresho_data=, model_path=, threshold=, tolerance=, rand_seed=);

/* The saved code is used to compute predictions on the holdout set */
data work.thresho_set_pred;
set &thresho_data.;
%include "&model_path.";
run;

/* Calculate holdout set errors, P_Class1 >= 0.5 -> predicted class = 1 */
data work.thresho_set_error;
set work.thresho_set_pred;
pred_class = round(P_Class1);
if &y. = pred_class then pred_error = 0;
else pred_error = 1;
run;

/* Calculate MSE for holdout set */
proc summary data=work.thresho_set_error;
var pred_error;
output out=work.pred_mse mean(pred_error)=holdout_mse;
run;

/* Thresholdout algorithm */
/* Thresholdout returns the mean classification error so that the holdout set can be reused */
data work.thresholdout_mse_&model_number.(drop=holdout_mse);
call streaminit(&rand_seed.);
merge &model_data.(drop=_TYPE_ _FREQ_) work.pred_mse(drop=_TYPE_ _FREQ_);
model_id = &model_number..;
if abs(final_mse - holdout_mse) < &threshold. + rand('NORMAL', 0, &tolerance.) then out_mse = final_mse;
else out_mse = holdout_mse + rand('NORMAL', 0, &tolerance.);
run;

/* Drop tables with data not to be looked at when doing adaptive data analysis */
proc sql;
drop table work.thresho_set_pred;
drop table work.thresho_set_error;
drop table work.pred_mse;
quit;

%mend thresholdout;

%thresholdout(model_data=work.cvk_final_mse_&model_number., y=Class, thresho_data=work.data_thresho, model_path=C:\codeSAS\myModels\genmod_model_final_&model_number..sas, threshold=&th_val., tolerance=&tol_val., rand_seed=1);