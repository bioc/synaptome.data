## ----loadPackages, include=FALSE, cache=FALSE------------------------------------------------------------------------------------
## load additional packages in this chunk
library(pander)
library(knitr)
library(ggplot2)
library(DBI)
library(reshape2)
library(RSQLite)
library(plyr)
library(dtplyr)
library(dbplyr)

dbname<-"synaptic.proteome_SR_20210704.db.sqlite"
recreate<-TRUE

#'
## ----setup, include=FALSE, cache=FALSE-------------------------------------------------------------------------------------------
## Pander options
panderOptions("digits", 3)
panderOptions("table.split.table", 160)


#'
## ----functions, include=FALSE----------------------------------------------------------------------------------------------------
ddlBR<-paste("CREATE TABLE BrainRegion (",
"  ID          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ",
"  Name        varchar(255) NOT NULL UNIQUE, ",
"  Description varchar(4255), ",
"  InterlexID   varchar(255), ",
"  ParentID    integer(10) , ",
"  FOREIGN KEY(ParentID) REFERENCES BrainRegion(ID));")
ddlG<-paste("CREATE TABLE Gene (",
"  ID          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ",
"  MGI         varchar(255), ",
"  HumanEntrez integer(10), ",
"  MouseEntrez integer(10), ",
"  HumanName   varchar(255), ",
"  MouseName   varchar(255), ",
"  RatEntrez   integer(10), ",
"  RatName     varchar(255));")
ddlL<-paste("CREATE TABLE Localisation (",
"  ID          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ",
"  Name        varchar(255) UNIQUE, ",
"  Description varchar(4255));")
ddlM<-paste("CREATE TABLE Method (",
"  ID          INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ",
"  Name        varchar(255) NOT NULL UNIQUE, ",
"  Description varchar(4255));")
ddlP<-paste("CREATE TABLE Paper (",
"  PMID        numeric(19, 0) NOT NULL, ",
"  Year        integer(10) NOT NULL, ",
"  Name        varchar(255) NOT NULL UNIQUE, ",
"  Description varchar(1255), ",
"  PRIMARY KEY (PMID));")
ddlPG<-paste("CREATE TABLE PaperGene (",
"  GeneID         integer(10) NOT NULL, ",
"  PaperPMID      numeric(19, 0) NOT NULL, ",
"  SpeciesTaxID   integer(10) NOT NULL, ",
"  BrainRegionID  integer(10) NOT NULL, ",
"  LocalisationID integer(10) NOT NULL, ",
"  MethodID       integer(10) NOT NULL, ",
"  PRIMARY KEY (GeneID, ",
"  PaperPMID, ",
"  BrainRegionID, ",
"  LocalisationID), ",
"  FOREIGN KEY(GeneID) REFERENCES Gene(ID), ",
"  FOREIGN KEY(PaperPMID) REFERENCES Paper(PMID), ",
"  FOREIGN KEY(SpeciesTaxID) REFERENCES Species(TaxID), ",
"  FOREIGN KEY(BrainRegionID) REFERENCES BrainRegion(ID), ",
"  FOREIGN KEY(LocalisationID) REFERENCES Localisation(ID), ",
"  FOREIGN KEY(MethodID) REFERENCES Method(ID));")
ddlPPI<-paste("CREATE TABLE PPI (",
"  ID     INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ",
"  A      integer(10) NOT NULL, ",
"  B      integer(10) NOT NULL, ",
"  type   varchar(255) NOT NULL, ",
"  method varchar(255) NOT NULL, ",
#"  pmid   integer(10), ",
"  taxID  integer(10) NOT NULL, ",
"  FOREIGN KEY(A) REFERENCES Gene(ID), ",
"  FOREIGN KEY(B) REFERENCES Gene(ID));")
ddlS<-paste("CREATE TABLE Species (",
"  TaxID   INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, ",
"  Name    varchar(255) NOT NULL UNIQUE, ",
"  SciName varchar(255));")
ddlUGE<-paste("CREATE UNIQUE INDEX GeneUI ",
"  ON Gene (HumanEntrez, MouseEntrez);")
ddlGO <- paste("CREATE TABLE GO (",
"  GOID        varchar(255) NOT NULL, ",
"  Description varchar(255) NOT NULL, ",
"  Domain      varchar(255) NOT NULL, ",
"  PRIMARY KEY (GOID));")
ddlGOGene <- paste("CREATE TABLE GOGene (",
"  GeneID   integer(10) NOT NULL, ",
"  SpecieID integer(10) NOT NULL, ",
"  GOID     varchar(255) NOT NULL, ",
"  FOREIGN KEY(GeneID) REFERENCES Gene(ID), ",
"  FOREIGN KEY(SpecieID) REFERENCES Species(TaxID), ",
"  FOREIGN KEY(GOID) REFERENCES GO(GOID));")
ddlD <- paste("CREATE TABLE Disease (",
"  HDOID       varchar(255) NOT NULL, ",
"  Description varchar(255), ",
"  PRIMARY KEY (HDOID));")
ddlDG <- paste("CREATE TABLE DiseaseGene (",
"  GeneID integer(10) NOT NULL, ",
"  HDOID  varchar(255) NOT NULL, ",
"  FOREIGN KEY(GeneID) REFERENCES Gene(ID), ",
"  FOREIGN KEY(HDOID) REFERENCES Disease(HDOID));")
ddlMO <- paste("CREATE TABLE GeneToModel (",
"  GeneID integer(10) NOT NULL, ",
"  EntityID varchar(255) NOT NULL, ",
"  PMID numeric(19, 0) NOT NULL, ",
"  FOREIGN KEY(GeneID) REFERENCES Gene(ID), ",
"  FOREIGN KEY(PMID) REFERENCES Paper(PMID));")
ddlBRS <- paste("CREATE TABLE SpecieRegion (",
"  BrainRegionID integer(10) NOT NULL, ",
"  TaxID         integer(10) NOT NULL, ",
"  FOREIGN KEY(TaxID) REFERENCES Species(TaxID), ",
"  FOREIGN KEY(BrainRegionID) REFERENCES BrainRegion(ID));")
ddlPapPPI <- paste("CREATE TABLE PaperPPI (",
  "PMID NUMERIC(19, 0) NOT NULL, ",
  "PPID     integer(10) NOT NULL, ",
  "FOREIGN KEY(PMID) REFERENCES Paper(PMID), ",
  "FOREIGN KEY(PPID) REFERENCES PPI(ID));")
ddlV1<-paste("CREATE VIEW FullGenePaper AS",
"SELECT p.GeneID,LocalisationID, MGI,HumanEntrez,MouseEntrez,HumanName,MouseName,PaperPMID,SpeciesTaxID,MethodID",
"FROM Gene  g join PaperGene p on g.ID=p.GeneID;")
ddlV2<-paste("CREATE VIEW FullGenefullPaper AS",
"SELECT p.GeneID,l.Name AS Localisation, ",
"MGI,HumanEntrez,MouseEntrez,HumanName,",
"MouseName,PaperPMID,a.Name AS Paper,",
"a.Year AS Year,",
"SpeciesTaxID,MethodID",
"FROM Gene  g join PaperGene p on g.ID=p.GeneID ",
"join Localisation l on l.ID = p.LocalisationID ",
"join Paper a on a.PMID = p.PaperPMID;")
ddlV3<-paste("CREATE VIEW FullGeneFullPaperFullRegion AS",
"    SELECT p.GeneID,",
"           l.Name AS Localisation,",
"           MGI,",
"           HumanEntrez,",
"           MouseEntrez,",
"           HumanName,",
"           MouseName,",
"           PaperPMID,",
"           a.Name AS Paper,",
"           a.Year AS Year,",
"           SpeciesTaxID,",
"           MethodID,",
"           b.Name AS BrainRegion",
"      FROM Gene g",
"           JOIN",
"           PaperGene p ON g.ID = p.GeneID",
"           JOIN",
"           Localisation l ON l.ID = p.LocalisationID",
"           JOIN",
"           Paper a ON a.PMID = p.PaperPMID",
"           JOIN",
"           BrainRegion b ON b.ID = p.BrainRegionID;")
ddlV4<-paste("CREATE VIEW FullGeneFullDisease AS",
"    SELECT HumanEntrez,",
"           HumanName,",
"           d.HDOID,",
"           d.Description",
"      FROM Gene g",
"           JOIN",
"           DiseaseGene dg ON g.ID = dg.GeneID",
"           JOIN",
"           disease d ON dg.HDOID = d.HDOID;")

#'
#' # Make database
#'
## ----open.db, warning=FALSE,echo=FALSE-------------------------------------------------------------------------------------------
if(recreate){
  unlink(dbname)
}
mydb <- dbConnect(RSQLite::SQLite(), dbname)
dbSendStatement(mydb,ddlBR)
dbSendStatement(mydb,ddlG)
dbSendStatement(mydb,ddlL)
dbSendStatement(mydb,ddlM)
dbSendStatement(mydb,ddlP)
dbSendStatement(mydb,ddlPG)
dbSendStatement(mydb,ddlPPI)
dbSendStatement(mydb,ddlS)
dbSendStatement(mydb,ddlUGE)
dbSendStatement(mydb,ddlGO)
dbSendStatement(mydb,ddlGOGene)
dbSendStatement(mydb,ddlD)
dbSendStatement(mydb,ddlDG)
dbSendStatement(mydb,ddlBRS)
dbSendStatement(mydb,ddlMO)
dbSendStatement(mydb,ddlPapPPI)
dbSendStatement(mydb,ddlV1)
dbSendStatement(mydb,ddlV2)
dbSendStatement(mydb,ddlV3)
dbSendStatement(mydb,ddlV4)

#'
#' # Populate database
#' ## Method
## ----add.methods-----------------------------------------------------------------------------------------------------------------
method.df<-data.frame(ID=1:2,name=c("Shotgun","Target"),description=c("Shotgun","Target"))
dbWriteTable(mydb, "method", method.df,append=TRUE)

#'
#' ## Species
## ----add.species-----------------------------------------------------------------------------------------------------------------
species.df<-data.frame(TaxID=c(9606,10090,10116),
                       Name=c("human","mouse","rat"),
                       SciName=c("Homo sapiens",
                                 "Mus musculus",
                                 "Rattus norvegicus"))
dbWriteTable(mydb, "species", species.df,append=TRUE)

#'
#' ## Brain Regions
## ----add.brain.regions-----------------------------------------------------------------------------------------------------------
brainReg.df <- read.table("~/Documents/Synaptic proteome paper/db/Up_March2020/BrainRegions.txt", sep = "\t", header = TRUE, stringsAsFactors = FALSE )
brp <- read.delim("~/Documents/Synaptic proteome paper/db/Up_March2020/BrainRegPapers.txt", sep = "\t", header = T, stringsAsFactors = FALSE)
idxBR <- match(brp$Name, brainReg.df$Name)

dbWriteTable(mydb, "BrainRegion", brainReg.df,append=TRUE)


#' ## SpecieRegion
#'
## ----Specie.Region---------------------------------------------------------------------------------------------------------------
sbr <- read.delim("~/Documents/Synaptic proteome paper/db/Up_March2020/BrainRegionSpecie.txt", sep = "\t", header = TRUE, stringsAsFactors = FALSE)
dbWriteTable(mydb, "SpecieRegion", sbr,append=TRUE)


#'
#' ## Localisation
## ----add.location----------------------------------------------------------------------------------------------------------------
loc.df<-data.frame(ID=1:3,
                   Name=c("Postsynaptic",
                          "Presynaptic",
                          "Synaptosome"),
                   Description=c("Postsynaptic",
                          "Presynaptic",
                          "Synaptosome"))
dbWriteTable(mydb, "localisation", loc.df,append=TRUE)

#'
#'
#' ## Papers
## ----prepare.papers--------------------------------------------------------------------------------------------------------------
papers<-read.delim("~/Documents/Synaptic proteome paper/db/Up_March2020/Paper_DB_summary_April21.txt",sep='\t',header = TRUE, stringsAsFactors = FALSE)
pmed <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/pubmed.data.full.csv", stringsAsFactors = FALSE)
any(papers$PubMed %in% pmed$PMID)
pmed.df <- unique(pmed[,c("PMID", "Year","name")])
names(pmed.df) <- c("PMID","Year","Name")
pmed.df$Description <- NA
p.fq<-as.data.frame(table(pmed.df$Name))
p.fq<-p.fq[p.fq$Freq>1,]
for(nm in p.fq$Var1){
  idx.pfq<-which(pmed.df$Name==nm)
  pmed.df$Name[idx.pfq]<-paste0(pmed.df$Name[idx.pfq],letters[1:length(idx.pfq)])
}
pmed.df$Name[which(pmed.df$Name %in% papers$Name)]<-paste0(
  pmed.df$Name[which(pmed.df$Name %in% papers$Name)],'a')
p.df<-unique(papers[,c('PubMed','Year','Name','Short.description')])
names(p.df)<-c("PMID","Year","Name","Description")
p.df <- rbind(p.df, pmed.df)
p.df<-p.df[!is.na(p.df$Year),]
papers$taxId<-species.df$TaxID[match(papers$Species,species.df$Name)]
papers$methodId<-2
papers$methodId[papers$shotgun=="YES"]<-1
dbWriteTable(mydb, "paper", p.df,append=TRUE)

#'
#' ## Genes
#' ### Genes table
## ----full.genes------------------------------------------------------------------------------------------------------------------
full <- read.delim("~/Documents/Synaptic proteome paper/db/Up_March2020/Full_DB_April21.txt", sep = "\t", header = T, stringsAsFactors = FALSE)
full$ID<-1:dim(full)[1]
fg.df<- full[,c(dim(full)[2],1:7)]
names(fg.df)<-c('ID',
                'MGI',
                'MouseEntrez',
                'MouseName',
                'HumanEntrez',
                'HumanName',
                'RatEntrez',
                'RatName')
dbWriteTable(mydb, "gene", fg.df,append=TRUE)
fg.df$surkey<-paste(fg.df$MouseEntrez,
                    fg.df$HumanEntrez,
                    sep = ":")


#'
#'
#' ### Postsynaptic
#'
## ----prepare.postsynaptic--------------------------------------------------------------------------------------------------------
gene1<-read.delim("~/Documents/Synaptic proteome paper/db/Up_March2020/PSD_db_Oct20.txt",sep ='\t',header=TRUE, stringsAsFactors = FALSE)
gene1 <- gene1[, -c(dim(gene1)[2])]
g1.df<-gene1[,1:5]
names(g1.df)<-c('mgi',
                'mouseentrez',
                'mousename',
                'humanentrez',
                'humanname')
surKey<-paste(g1.df$mouseentrez,g1.df$humanentrez,sep=":")
idx<-match(surKey,fg.df$surkey)
g1.df$id<-fg.df$ID[idx]
gene1$id<-fg.df$ID[idx]
mg1<-melt(gene1[,c(6:dim(gene1)[2])],id="id")
mg1<-mg1[mg1$value==1,]
mg1$locID=1
idx<-match(mg1$variable,p.df$Name)
mg1$pmid<-p.df$PMID[idx]
mg1$taxId<-papers$taxId[idx]
mg1$methodId<-papers$methodId[idx]
l <- list()
for (i in 1:dim(brp)[1]){
  if (any(mg1$variable == brp$Paper[i])){
  mgt <- mg1[mg1$variable == brp$Paper[i],]
  mgt$BrainRegionID <- idxBR[i]
  l[[length(l)+1]] <- mgt
  }
}
mag1 <-do.call(rbind,l)

#'
#' ### Presynaptic
## ----prepare.presynaptic---------------------------------------------------------------------------------------------------------
gene2<-read.delim("~/Documents/Synaptic proteome paper/db/Up_March2020/Pres_DB_April21.txt",sep ='\t',header=TRUE, stringsAsFactors = FALSE)
gene2 <- gene2[, -c(dim(gene2)[2])]
g2.df<-gene2[,c("MGI.ID",
                "MOUSE.ENTREZ.ID",
                "MOUSE.GENE.NAME",
                "HUMAN.ENTREZ.ID",
                "HUMAN.GENE.NAME")]
names(g2.df)<-c('mgi',
                'mouseentrez',
                'mousename',
                'humanentrez',
                'humanname')
surKey<-paste(g2.df$mouseentrez,g2.df$humanentrez,sep=":")
idx<-match(surKey,fg.df$surkey)
g2.df$id<-fg.df$ID[idx]
gene2$id<-fg.df$ID[idx]
mg2<-melt(gene2[,c(11:dim(gene2)[2])],id="id")
mg2<-mg2[mg2$value==1,]
mg2$locID=2
idx<-match(mg2$variable,p.df$Name)
mg2$pmid<-p.df$PMID[idx]
mg2$taxId<-papers$taxId[idx]
mg2$methodId<-papers$methodId[idx]
l <- list()
for (i in 1:dim(brp)[1]){
  if (any(mg2$variable == brp$Paper[i])){
  mgt <- mg2[mg2$variable == brp$Paper[i],]
  mgt$BrainRegionID <- idxBR[i]
  l[[length(l)+1]] <- mgt
  }
}
mag2 <-do.call(rbind,l)

#'
#' ### Synaptosome
## ----prepare.synaptosome---------------------------------------------------------------------------------------------------------
gene3<-read.delim("~/Documents/Synaptic proteome paper/db/Up_March2020/Syn_DB_April21.txt",sep ='\t',header=TRUE, stringsAsFactors = FALSE)
g3.df<-gene3[,1:4]
names(g3.df)<-c('mouseentrez',
                'mousename',
                'humanentrez',
                'humanname')
surKey<-paste(g3.df$mouseentrez,g3.df$humanentrez,sep=":")
idx<-match(surKey,fg.df$surkey)
g3.df$id<-fg.df$ID[idx]
gene3$id<-fg.df$ID[idx]
mg3<-melt(gene3[,c(5:dim(gene3)[2])],id="id")
mg3<-mg3[mg3$value==1,]
mg3$locID=3
idx<-match(mg3$variable,p.df$Name)
mg3$pmid<-p.df$PMID[idx]
mg3$taxId<-papers$taxId[idx]
mg3$methodId<-papers$methodId[idx]
l <- list()
for (i in 1:dim(brp)[1]){
  if (any(mg3$variable == brp$Paper[i])){
  mgt <- mg3[mg3$variable == brp$Paper[i],]
  mgt$BrainRegionID <- idxBR[i]
  l[[length(l)+1]] <- mgt
  }
}
mag3 <-do.call(rbind,l)

#'
#' ### COmbine all localisation
#'
## ----combine.and.load------------------------------------------------------------------------------------------------------------
totGene<-rbind(mag1[,c("id","locID","pmid","taxId","methodId", 'BrainRegionID')],
               mag2[,c("id","locID","pmid","taxId","methodId", 'BrainRegionID')],
               mag3[,c("id","locID","pmid","taxId","methodId", 'BrainRegionID')])
names(totGene)<-c("GeneID","LocalisationID","PaperPMID","SpeciesTaxID",
                  "MethodID", 'BrainRegionID')
totGene<-totGene[,c("GeneID",
"PaperPMID",
"SpeciesTaxID",
"BrainRegionID",
"LocalisationID",
"MethodID")]
dbWriteTable(mydb, "papergene", totGene,append=TRUE)

#'
#' # PPI
## ----load.ppi--------------------------------------------------------------------------------------------------------------------
ppi.df<-read.delim("~/Documents/Synaptic proteome paper/db/Up_March2020/PPI_DB_April21.txt",sep = "\t", header = TRUE, stringsAsFactors = FALSE)
idxA<-match(ppi.df$entA,fg.df$HumanEntrez)
idxB<-match(ppi.df$entB,fg.df$HumanEntrez)
ppi.df$A<-fg.df$ID[idxA]
ppi.df$B<-fg.df$ID[idxB]
ppi.df$taxId<-ppi.df$taxA
ppi.df$ID<- 1:dim(ppi.df)[1]
ppi.t<-ppi.df[,c('ID','A','B','type','method','taxId')]
names(ppi.t)<-c('ID','A','B','type','method','taxID')
dbWriteTable(mydb, "ppi", ppi.t,append=TRUE)

#'
## ----load.paper.ppi--------------------------------------------------------------------------------------------------------------
pmidx<-match(ppi.df$pmid,papers$PubMed)
idx<-which(!is.na(pmidx))
pap.ppi<-data.frame(PMID=papers$PubMed[pmidx[idx]],PPID=ppi.df$ID[idx])
dbWriteTable(mydb, "PaperPPI", pap.ppi,append=TRUE)
length(which(is.na(pmidx)))

#'
#' # GO
## ----load.GO---------------------------------------------------------------------------------------------------------------------
bph <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Human_BP.csv", sep = "\t", header = FALSE)
bpm <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Mouse_BP.csv", sep = "\t", header = FALSE)
bpr <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Rat_BP.csv", sep = "\t", header = FALSE)
BP <- rbind(bph[, c(1,2)], bpm[, c(1,2)], bpr[, c(1,2)])
BP <- unique(BP)
names(BP) <- c("GOID", "Description")
BP$Domain <- "BP"
cch <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Human_CC.csv", sep = "\t", header = FALSE)
ccm <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Mouse_CC.csv", sep = "\t", header = FALSE)
ccr <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Rat_CC.csv", sep = "\t", header = FALSE)
CC <- rbind(cch[, c(1,2)], ccm[, c(1,2)], ccr[, c(1,2)])
CC <- unique(CC)
names(CC) <- c("GOID", "Description")
CC$Domain <- "CC"
mfh <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Human_MF.csv", sep = "\t", header = FALSE)
mfm <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Mouse_MF.csv", sep = "\t", header = FALSE)
mfr <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Rat_MF.csv", sep = "\t", header = FALSE)
MF <- rbind(mfh[, c(1,2)], mfm[, c(1,2)], mfr[, c(1,2)])
MF <- unique(MF)
names(MF) <- c("GOID", "Description")
MF$Domain <- "MF"
df.go <- rbind(BP,CC,MF)
dbWriteTable(mydb, "GO", df.go, append=TRUE)


#' # GoGene
## ----load.GoGene-----------------------------------------------------------------------------------------------------------------
bph<- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Human_BP.csv", sep = "\t", header = FALSE)
bph$SpecieID <- "9606"
idx <- match(bph$V3,fg.df$HumanEntrez)
bph$GeneID <- fg.df$ID[idx]
bph.t <- bph[, c(5,4,1)]
head(bph.t)
names(bph.t) <- c("GeneID", "SpecieID","GOID")
dbWriteTable(mydb, "GOGene", bph.t, append=TRUE)

bpm<- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Mouse_BP.csv", sep = "\t", header = FALSE)
bpm$SpecieID <- "10090"
idx <- match(bpm$V3,fg.df$MouseEntrez)
bpm$GeneID <- fg.df$ID[idx]
bpm.t <- bpm[, c(5,4,1)]
head(bpm.t)
names(bpm.t) <- c("GeneID", "SpecieID","GOID")
dbWriteTable(mydb, "GOGene", bpm.t, append=TRUE)

bpr<- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Rat_BP.csv", sep = "\t", header = FALSE)
bpr$SpecieID <- "10116"
idx <- match(bpr$V3,fg.df$RatEntrez)
bpr$GeneID <- fg.df$ID[idx]
bpr.t <- bpr[, c(5,4,1)]
head(bpr.t)
names(bpr.t) <- c("GeneID", "SpecieID","GOID")
dbWriteTable(mydb, "GOGene", bpr.t, append=TRUE)

cch<- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Human_CC.csv", sep = "\t", header = FALSE)
cch$SpecieID <- "9606"
idx <- match(cch$V3,fg.df$HumanEntrez)
cch$GeneID <- fg.df$ID[idx]
cch.t <- cch[, c(5,4,1)]
head(cch.t)
names(cch.t) <- c("GeneID", "SpecieID","GOID")
dbWriteTable(mydb, "GOGene", cch.t, append=TRUE)

ccm<- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Mouse_CC.csv", sep = "\t", header = FALSE)
ccm$SpecieID <- "10090"
idx <- match(ccm$V3,fg.df$MouseEntrez)
ccm$GeneID <- fg.df$ID[idx]
ccm.t <- ccm[, c(5,4,1)]
head(ccm.t)
names(ccm.t) <- c("GeneID", "SpecieID","GOID")
dbWriteTable(mydb, "GOGene", ccm.t, append=TRUE)

ccr<- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Rat_CC.csv", sep = "\t", header = FALSE)
ccr$SpecieID <- "10116"
idx <- match(ccr$V3,fg.df$RatEntrez)
ccr$GeneID <- fg.df$ID[idx]
ccr.t <- ccr[, c(5,4,1)]
head(ccr.t)
names(ccr.t) <- c("GeneID", "SpecieID","GOID")
dbWriteTable(mydb, "GOGene", ccr.t, append=TRUE)

mfh<- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Human_MF.csv", sep = "\t", header = FALSE)
mfh$SpecieID <- "9606"
idx <- match(mfh$V3,fg.df$HumanEntrez)
mfh$GeneID <- fg.df$ID[idx]
mfh.t <- mfh[, c(5,4,1)]
head(mfh.t)
names(mfh.t) <- c("GeneID", "SpecieID","GOID")
dbWriteTable(mydb, "GOGene", mfh.t, append=TRUE)

mfm<- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Mouse_MF.csv", sep = "\t", header = FALSE)
mfm$SpecieID <- "10090"
idx <- match(mfm$V3,fg.df$MouseEntrez)
mfm$GeneID <- fg.df$ID[idx]
mfm.t <- mfm[, c(5,4,1)]
head(mfm.t)
names(mfm.t) <- c("GeneID", "SpecieID","GOID")
dbWriteTable(mydb, "GOGene", mfm.t, append=TRUE)

mfr<- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_Rat_MF.csv", sep = "\t", header = FALSE)
mfr$SpecieID <- "10116"
idx <- match(mfr$V3,fg.df$RatEntrez)
mfr$GeneID <- fg.df$ID[idx]
mfr.t <- mfr[, c(5,4,1)]
head(mfr.t)
names(mfr.t) <- c("GeneID", "SpecieID","GOID")
dbWriteTable(mydb, "GOGene", mfr.t, append=TRUE)


#' # Disease
## ----Add.disease-----------------------------------------------------------------------------------------------------------------
hdo <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_human_HDO.csv", sep = "\t", header = FALSE, stringsAsFactors = FALSE)
hdo <- hdo[, c(1,2)]
hdoU <- unique(hdo)
names(hdoU) <- c("HDOID","Description")
dbWriteTable(mydb, "Disease", hdoU, append=TRUE)


#' # DiseaseGene
#'
## ----add.diseaseGene-------------------------------------------------------------------------------------------------------------
hdo <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/flatfile_human_HDO.csv", sep = "\t", header = FALSE, stringsAsFactors = FALSE)
idx <- match(hdo$V3, fg.df$HumanEntrez)
hdo$GeneID <- fg.df$ID[idx]
hdog <- hdo[, c(4,1)]
names(hdog) <- c("GeneID", "HDOID")
dbWriteTable(mydb, "DiseaseGene", hdog, append=TRUE)

#'
#' # GeneToModel
#'
## ----add.model-------------------------------------------------------------------------------------------------------------------
gm <- read.csv("~/Documents/Synaptic proteome paper/db/Up_March2020/genes-in-models.csv", sep = ",", header = TRUE, stringsAsFactors = FALSE)
idx <- match(gm$ENTREZ.ID, fg.df$HumanEntrez)
gm$GeneID <- fg.df$ID[idx]
gmg <- gm[!is.na(gm$GeneID),]
gmgg <- gmg[, c(8,2,3)]
names(gmgg) <- c("GeneID","EntityID","PMID")
dbWriteTable(mydb, "GeneToModel", gmgg, append=TRUE)

#'
#'
#' # Close database
#'
## ----disconnect.db---------------------------------------------------------------------------------------------------------------
dbDisconnect(mydb)

#'
#'
#' ### Session Info
## ----sessionInfo, echo=FALSE, results='asis', class='text', warning=FALSE--------------------------------------------------------
c<-devtools::session_info()
pander(t(data.frame(c(c$platform))))
pander(as.data.frame(c$packages)[,-c(4,5,10,11)])

#'
