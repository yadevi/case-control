################################################################################################
# NAME: study.r
# AUTHORS: Ellie Matthay, Catherine Li, Chris Rowe
# DATE STARTED: 12/15/2017    
# PURPOSE: Define a function to apply various survey sampling and case control procedures to 
#            test the performance of different approaches to selecting controls from external 
#            data sources with complex sampling methods.
# UPDATES: [date]: XX
################################################################################################

####
# Create a function that will apply the different study designs and analyses
####

study <- function(seed, # random seed to make sampling replicable
                  cctype = "cumulative", # case control type. Options will be:
                    # "cumulative"  for cumulative case-control
                    # "density" for density-sampled
                  samp   = "srs", # sampling of controls. Options will be:
                    # "srs" for simple random sample
                    # "sps" for simple probability sample with know probability of selection for each individual
                    # "clustered1" for single stage clustered design
                    # "clustered2" for two-stage clustered design 
                    # "stratified" for single stage stratified design
                  ratio = 1, # ratio of controls to cases
                  data # argument to provide the population data. Population data will take the format of the pop data we've created. 
                   # any other options here TBD
) {
  
  ####### PHASE 1: source of cases and controls -- SRS, complex survey, etc. 
  set.seed(seed)
  
  # Select cases and controls
  allcases    <- data[data$Y==1,]
  allcontrols <- data[data$Y==0,]

  # Create Case Weights
  allcases$sampweight <- 1
  
  if (samp=="srs") { # simple random sample of controls
    
    control.samp <- allcontrols[sample(1:nrow(allcontrols), size = nrow(allcases)*ratio, replace=F),] 
    control.samp$sampweight <- nrow(allcases)*ratio / nrow(allcontrols)
    
  } else if (samp=="sps") {  # simple probability sample of controls with known probability of selection for each individual
    
    allcontrols$sampprob <- runif(nrow(allcontrols), 0, 1) # generate probability of being selected
    control.samp <- allcontrols[sample(1:nrow(allcontrols), size = nrow(allcases)*ratio, prob = allcontrols$sampprob, replace=F),] # Sample control units
    control.samp$sampweight <- 1/control.samp$sampprob # Calculate Weights
    control.samp <- subset(control.samp, select = -sampprob) # Remove unneeded column  
    allcontrols <- subset(allcontrols, select = -sampprob) # Remove unneeded column 
 
  } else if (samp=="clustered1") { # single state cluster design in which clusters are sampled and all individuals within selected clusters are selected.          
    
    cluster <- aggregate(data.frame(popsize = allcontrols$cluster), list(cluster = allcontrols$cluster), length) # Calculate cluster (i.e. cluster) population size to determine cluster sampling probability (proportional to cluster population size)
    cluster$cls.sampprob <- cluster$popsize/nrow(allcontrols) # Calculate cluster sampling probability
    cluster.samp <- cluster[sample(1:nrow(cluster), size = round((nrow(allcases)*ratio/mean(table(data$cluster)))/2,0), prob = cluster$cls.sampprob, replace=F),] # Sample clusters using cluster sampling probability; note difficulty in arriving at desired sample size
    control.samp <- allcontrols[allcontrols$cluster %in% cluster.samp[,"cluster"],] # Sample all controls from each of the randomly sampled clusters
    control.samp <- merge(control.samp, cluster.samp, by="cluster") # Merge cluster characteristics with sampled controls
    control.samp$sampweight <- 1/(control.samp$cls.sampprob) # Calculate sampling weight
    control.samp <- subset(control.samp, select = -c(popsize, cls.sampprob)) # Remove unneeded column
    control.samp <- control.samp[sample(1:nrow(control.samp)), ] # Order randomly
    rm(cluster,cluster.samp) # Remove unneeded objects      
    
  } else if (samp=="clustered2") { # two stage cluster design in which cluster are sampled and individuals are sampled from within selected clusters.

    puma <- aggregate(data.frame(popsize = allcontrols$puma), list(puma = allcontrols$puma), length) # Calculate cluster (i.e. PUMA) population size to determine cluster sampling probability (proportional to cluster population size)
    puma$cls.sampprob <- puma$popsize/nrow(allcontrols) # Calculate cluster sampling probability
    puma.samp <- puma[sample(1:nrow(puma), size = 143, prob = puma$cls.sampprob, replace=F),] # Sample 150 clusters using cluster sampling probability
    control.samp <- allcontrols[allcontrols$puma %in% puma.samp[,"puma"],] %>% group_by(puma) %>% sample_n(143)# Randomly sample 150 controls from each of the 150 selected clusters
    control.samp <- merge(control.samp, puma.samp, by="puma") # Merge cluster characteristics with sampled controls
    control.samp$sampprob <- 143/control.samp$popsize # Calculate individual within-cluster sampling probability (i.e. 150 divided by cluster population size)
    control.samp$sampweight <- 1/(control.samp$cls.sampprob*control.samp$sampprob) # Calculate Sampling Weight
    control.samp <- subset(control.samp, select = -c(popsize,cls.sampprob, sampprob)) # Remove unneeded columns
    control.samp <- control.samp[sample(1:nrow(control.samp)), ] # Order randomly
    rm(puma,puma.samp) # Remove unneeded objects

  } else if (samp=="stratified") {    
    
    allcontrols$strata2 <- as.numeric(cut(allcontrols$county,unique(quantile(allcontrols$county,seq(0,1,.1))),include.lowest=TRUE)) # Split counties into 8 strata
    stratainfo <- data.frame(table(allcontrols$strata2)) # Create dataframe for strata info for calculating sampling weights later
    stratainfo$size <- round((stratainfo$Freq/nrow(allcontrols))*(nrow(allcases)*ratio)) # Calculate sample size for each strata that is proportional to strata size
    colnames(stratainfo) <- c("strata2", "stratasize", "stratasampsize") # Rename strata data colunms for merging with sampled controls
    control.samp <- allcontrols[0,] # Create empty data.frame for samples
    for(i in 1:length(unique(allcontrols$strata2))) { # Sample controls proportional to strata size
      controls.strata <- allcontrols[allcontrols$strata2==i,]
      control.samp.strata <- controls.strata[sample(1:nrow(controls.strata), size = stratainfo$stratasampsize[i], replace=F),]   
      control.samp <- rbind(control.samp,control.samp.strata)
    }
    control.samp <- merge(control.samp, stratainfo, by="strata2") # Merge in strata info to calculate weights
    control.samp$sampweight <- 1/(control.samp$stratasampsize/control.samp$stratasize) # Calculate Sampling Weight 
    control.samp <- subset(control.samp, select = -c(strata2, stratasize, stratasampsize)) # Remove unneeded columns
    control.samp <- control.samp[sample(1:nrow(control.samp)), ] # Order randomly
    rm(control.samp.strata, controls.strata, stratainfo, i) # Remove unneeded objects
  
  } else if (samp=="ACS") {
    
  } else if (samp=="NHANES") {
    
  }
  
  ####### PHASE 2: implement case-control - cumulative or density sampled, and analyse the data appropriately
  set.seed(seed+1)
  
  # CUMULATIVE CASE-CONTROL
  if (cctype=="cumulative") {
    
    # Apply design
    sample <- rbind(allcases, control.samp) 
    
    # Run model
    mod <- glm(Y ~ A + black + asian + hispanic + otherrace + age_25_34 + age_35_44 + age_45_54 + age_55_64 + age_over64 + male + 
                 educ_ged + educ_hs + educ_somecollege + educ_associates + educ_bachelors + educ_advdegree, 
               data=sample, family='binomial', weights = sampweight)
    
    # Pull the main point estimate and CI
    est <- exp(coef(mod)[2])
    lower <- exp(coef(mod)[2] - 1.96*summary(mod)$coefficients[2,2])
    upper <- exp(coef(mod)[2] + 1.96*summary(mod)$coefficients[2,2])

    
  # DENSITY-SAMPLED CASE-CONTROL
  } else if (cctype=="density") {
    
    # Apply design
    presample <- rbind(allcases, control.samp) 
    sample <- ccwc(entry=0, exit=time, fail=Y, origin=0, controls=ratio, 
                   #match=list(), # use this argument for variables we want to match on
      include=list(A,black,asian,hispanic,otherrace,age_25_34,age_35_44,
                   age_45_54,age_55_64,age_over64,male,educ_ged,educ_hs,educ_somecollege,
                   educ_associates,educ_bachelors,educ_advdegree,sampweight), data=presample, silent=FALSE)
    
    # Run model
    mod <- clogit(Fail ~ A + black + asian + hispanic + otherrace + age_25_34 + age_35_44 + age_45_54 + age_55_64 + age_over64 + male + 
                    educ_ged + educ_hs + educ_somecollege + educ_associates + educ_bachelors + educ_advdegree + strata(Set), 
                  data = sample, weights = sampweight, method = "efron")

    # Pull the main point estimate and CI
    est <- exp(coef(mod)[1])
    lower <- exp(coef(mod)[1] - 1.96*summary(mod)$coefficients[1,3])
    upper <- exp(coef(mod)[1] + 1.96*summary(mod)$coefficients[1,3])
  }
  
  # Return the sampled data, model object, point estimate, and CI
  return(list(sample=sample, mod=mod, est=est, lower=lower, upper=upper))
}

# END