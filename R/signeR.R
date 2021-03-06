################################################################################
# Parameters:
#
# Input data
# M: matrix of mutation counts, each row corresponds to one sample 
#   (dimension = nsamples x 96). Can be a path to a file.
# Mheader: if M is to be read from a file, does it contains a header line? 
#          Otherwise, if M is a matrix, does it have mutations and samples as 
#          colnames and rownames?  
# samples: if "rows" M is supposed to contain one sample per row. 
#          Otherwise, one sample per column is expected.
# Opport: matrix of mutation opportunities, each column corresponds to 
#         one sample (96 x nsamples)
# Opportheader: if Opport is to be read from a file, does it contains 
#               a header line?
#
# Numerical parameters of the model
# nsig: number of signatures, which can be provided or estimated 
#       by the algorithm
# nlim: range of possible values for the number of signatures
# try_all: if true, all possible values for n will be tested
# ap, bp: hyperparameters of rate parameters used to generate signatures 
#        (gamma distributions)
# ae, be: hyperparameters of rate parameters used to generate exposures 
#        (gamma distributions)
# lp: hyperparameters of shape parameters used to generate signatures 
#     (exponential distributions)
# le: hyperparameters of shape parameters used to generate exposures 
#     (exponential distributions)
# varp.ap: variance of the gamma distribution used to generate proposals for 
#          shape parameters of signatures
# varp.ae: variance of the gamma distribution used to generate proposals for 
#          shape parameters of exposures
#
# Sampler parameters
# testing_burn: number of burning iterations of the Gibbs sampler used to 
#               estimate the number of signatures in data. 
# testing_eval: number of iterations of the Gibbs sampler used to estimate 
#               the number of signatures in data. 
# main_burn: number of burning iterations of the final Gibbs sampler
# main_eval: number of iterations of the final Gibbs sampler
#
# Further options
# start: NMF algorithm used to generate initial values for signatures and 
#        exposures, options: "brunet","KL","lee","Frobenius","offset","nsNMF",
#                            "ls-nmf","pe-nmf","siNMF","snmf/r" or "snmf/l".
# estimate_hyper: if TRUE, algorithm estimates optimal values of 
#                 ap,bp,ae,be,lp,le. Start values can still be provided.
# EMit_lim: limit of EM iterations for the estimation of ap,bp,ae,be,lp,le.
################################################################################

signeR<-function(M, Mheader=TRUE, samples = "rows",
    Opport=NA, Oppheader=FALSE, 
    nsig=NA,nlim=c(NA,NA),try_all=FALSE,
    ap=NA,bp=NA,ae=NA,be=NA,lp=NA,le=NA,
    var.ap=10,var.ae=10,
    testing_burn=1000,testing_eval=1000,EM_eval=100,
    main_burn=10000,main_eval=2000,
    start='lee',estimate_hyper=FALSE,EMit_lim=100){
    if(is.character(M)){ 
        Mread<-as.matrix(read.table(M, header=Mheader, check.names=FALSE))
    }else if (is.data.frame(M)){
        Mread<-as.matrix(M)
    }else if (is.matrix(M)){
        Mread <- M
    }else stop("M should be a matrix, a data frame or a link to a file.")
    if(samples=="rows"){
        M<-t(Mread)
    }else{
        M<-as.matrix(Mread)
    }
    if(Mheader){
        samplenames<-colnames(M)
        mutnames<-rownames(M)
    }else{
        samplenames<-paste("sample",1:NCOL(M),sep="_")
        bases=c("A","C","G","T")
        mutnames<-paste(rep(bases,each=4,6),rep(c("C","T"),each=48),
            rep(bases,24),">",
            c(rep(bases[-2],each=16),rep(bases[-4],each=16)),sep="")
    }
    if(is.character(Opport)){ 
        Opportread<-as.matrix(read.table(Opport,header=Oppheader))
    }else if (is.data.frame(Opport)){
        Opportread<-as.matrix(Opport)
    }else if (is.matrix(Opport)){
        Opportread<-Opport
    }else if(is.na(Opport)){
        Opportread<-M
        Opportread[,]<-1
    }else{ 
        stop("Opport should be a matrix, a data frame, a link to a file or NA.")
    }
    if(all(dim(Opportread)==dim(M))){
        W<-Opportread
    }else if (all(dim(t(Opportread))==dim(M))){
        W<-t(Opportread)
    }else stop("Dimensions of M and Opport do not match.")
    if(sum(is.na(c(ap,bp,ae,be,lp,le)))>0){
        eh<-TRUE
        if(is.na(ap)) ap<-1
        if(is.na(bp)) bp<-1
        if(is.na(ae)) ae<-1
        if(is.na(be)) be<-1
        if(is.na(lp)) lp<-1
        if(is.na(le)) le<-1
    }else{
        eh<-estimate_hyper
    }
    if(is.na(nsig)){
        if(is.na(nlim[1])){
            Nmin <- 1
        }else{
            Nmin <- nlim[1]
        }
        if(is.na(nlim[2])){
            Nmax <- min(dim(M))-1
        }else{
            Nmax <- nlim[2]
        }
        if(try_all){
            step0 <- 1
        }else{
            step0 <- 2^max((floor(log2(Nmax-Nmin+1))-2),0)
        }
        cat(paste("Evaluating models with the number of signatures",
            " ranging from ",Nmin," to ",Nmax,", please be patient.\n",sep=""))
        Ops<-Optimal_sigs(testfun=function(n){
            ebNMF<-eBayesNMF(M,W,n,ap,bp,ae,be,lp,le,
                var.ap,var.ae,
                burn_it=testing_burn,eval_it=testing_eval,
                EM_eval_it=EM_eval,
                start=start,estimate_hyper=eh, EM_lim=EMit_lim,
                keep_param=FALSE)
            bics<-ebNMF[[3]]
            HH<-ebNMF[[9]]
            rm(ebNMF)
            return(list(median(bics),bics,HH))
        },
            liminf=Nmin,limsup=Nmax,step=step0,oldpoints=c(),
            oldvalues=c(),oldextra=list(),left_eval=NA)
        nopt<-Ops[[1]]
        Test_BICs<-list()
        HH<-list()
        for (k in 1:length(Ops[[2]])){
            Test_BICs[[k]]<-Ops[[4]][[k]][[1]]
            HH[[k]]<-Ops[[4]][[k]][[2]]
        }
        cat(paste("The optimal number of signatures is ",nopt,".\n",sep=""))
        BestHH<-HH[[which(Ops[[2]]==nopt)]]
        best_hyperparam<-BestHH[NROW(BestHH),]
        ap<-best_hyperparam$ap
        bp<-best_hyperparam$bp
        ae<-best_hyperparam$ae
        be<-best_hyperparam$be
        lp<-best_hyperparam$lp
        le<-best_hyperparam$le
        eh<-FALSE
    }else{
        nopt<-nsig
        Ops<-list(NA,NA,NA,NA)
        Test_BICs<-NA
        HH<-NA
    }
    #cat(paste("Running Gibbs sampler for ",nopt," signatures.\n",sep=""))
    Final_run<-eBayesNMF(M,W,n=nopt,ap,bp,ae,be,lp,le,
        var.ap,var.ae,
        burn_it=main_burn,eval_it=main_eval,EM_eval_it=EM_eval,
        start=start,estimate_hyper=eh, EM_lim=EMit_lim,
        keep_param=TRUE)
    SE<-Final_run[[4]]
    SE<-setSamples(SE,samplenames)
    SE<-setMutations(SE,mutnames)
    result<-list(Nsign=nopt,
        tested_n=Ops[[2]],
        Test_BICs=Test_BICs,
        Phat=Final_run[[1]],
        Ehat=Final_run[[2]],
        SignExposures=SE,
        BICs=Final_run[[3]],
        Hyper_paths=HH)
    #cat("Done.\n")
    return(result)
}


