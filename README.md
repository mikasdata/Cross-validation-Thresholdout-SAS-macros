# Cross-validation-Thresholdout-SAS-macros
Three SAS macros to perform cross-validation and to use the thresholdout algorithm to access a reusable holdout set.

The idea of a reusable holdout, it's implementation with the thresholdout algorithm and an explanation of what it means in adaptive data analysis can be found at this [Google Research Blog article.](https://research.googleblog.com/2015/08/the-reusable-holdout-preserving.html)

The macro

```
%macro cv_thresho_sets(data=, cv_data=, tho_data=, K=, rand_seed=);
```

splits the data into a training part to be used with cross-validation and a holdout set.

To perform cross-validation, run the macro

```
%macro cv_analysis(in_data=, y=, x=, model_id=, pred_path=, final_path=);
```

The thresholdout algorithm is implemented in the macro

```
%macro thresholdout(model_data=, y=, thresho_data=, model_path=, threshold=, tolerance=, rand_seed=);
```

The code includes description of parameters and an example on running the macros on sashelp.junkmail data.

To adjust the macros to other models it is necessary to modify the modelling code case by case:

```
%macro cv_analysis(in_data=, y=, x=, model_id=, pred_path=, final_path=);
 
 .
 .
 .
 
/* Train the model y = x on the training data */
/* Code for predicting the y values is saved to a file in pred_path */
proc genmod data=&in_data.(where=(group="train"));
model &y. = &x. / link=logit dist=binomial;
by Replicate;
code file="&pred_path.";
run;
 
 .
 .
 .
 
/* Final model y = x on whole data (without the holdout set) */
/* Code to make predictions is saved to a file final_path */
proc genmod data=&in_data.;
model &y. = &x. / link=logit dist=binomial;
code file="&final_path.";
run;
```
