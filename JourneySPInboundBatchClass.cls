/**
 * @description
 * This class is responsible for managing the batch process related to inbound shipments.
 * It updates shipment status on the related `J_Order__c` and logs the status update in the `J_SP_Status_Update__c` object.
 *
 * @author Vijay
 *
 * @version
 * 1.0
 */
global WITH SHARING class JourneySPInboundBatchClass implements Database.Batchable<sObject> {
    /**
 * @description Retrieves a query locator for processing batches of records from the `J_SP_Inbound__c` object.
 *              This method is part of the Database.Batchable interface implementation.
 *
 * @param bc The context object for the batch job.
 * @return A `Database.QueryLocator` object representing the batch of records to process.
 *
 * The query retrieves records from the `J_SP_Inbound__c` object where `J_Import_Status__c` equals `'Created'`.
 * The fields selected include detailed information such as claim details, insurance details, prescriber information,
 * product information, and other attributes required for processing.
 */

    global WITH SHARING Database.QueryLocator start(Database.BatchableContext bc) {
        // collect the batches of records or objects to be passed to executee
         
        String query = 'SELECT Id, Name, J_Claim_CoPay_Amount__c, J_Claim_CoPay_Applied__c, J_Claim_CoPay_Asst_Amt__c, J_Claim_CoPay_Elg__c,Enrollee_ID__c,'
+' J_Claim_Co_Ins_Amt__c, J_Claim_Co_Ins_percent__c, J_Claim_OOP_Met__c, J_Claim_PPayer_Paid_Amt__c,'
 +' J_Claim_Pt_Paid_Amt__c, J_Claim_Type__c, J_HCP_FirstName__c, J_HCP_LastName__c, J_HCP_Location__c, J_HCP_NPI__c, '
+' J_HUB_Patient_ID__c, J_INS_PP_BIN__c, J_INS_PP_Group_ID__c, J_INS_PP_ID__c, J_INS_PP_Name__c, J_INS_PP_PBM__c,'
 +' J_INS_PP_PCN__c, J_INS_PP_Plan_Name__c, J_INS_PP_Type__c, J_INS_SecP_BIN__c, J_INS_SecP_Group_ID__c, J_INS_SecP_ID__c,'
 +' J_INS_SecP_Name__c, J_INS_SecP_PCN__c, J_INS_SecP_Plan_Name__c, J_INS_SecP_State__c, J_INS_SecP_Type__c, '
+' J_Import_Status__c,J_Journey_Patient_Id__c, J_PA_Appeal_Date__c, J_PA_Date__c, J_PA_Exp_Date__c, J_PA_Req__c,'
 +' J_Product_Name__c, J_Program_Name__c, J_RX_DATE__c, J_RX_Day_Supply__c, J_RX_Dosage_Type__c, J_RX_Fill__c,'
 +' J_RX_NDC__c, J_RX_Num__c, J_RX_Qty__c, J_RX_Refil_Date__c, J_RX_Refil_Remaining__c, J_RX_Ship_Date__c,'
 +' J_RX_Shipment_ID__c, J_RX_Shipment_Type__c, J_RX_UOM__c, J_Record_Entry_Date__c, J_Record_type__c, J_SP_Loc_NCPDP__c,'
+' J_SP_Name__c, J_SP_Patient_Id__c, J_SP_Unique_Id__c, J_SR__c, J_Status_Date__c, J_Status__c, J_Sub_Status__c,'
 +' J_Concurrent_Txt__c, J_Error_Information__c, J_Patient_Gender__c, J_Patient_State__c, J_Prescriber_Address_1__c,'
 +' J_Prescriber_Address_2__c, J_Prescriber_City__c, J_Prescriber_DEA__c, J_Prescriber_Fax__c, J_Prescriber_Phone__c,'
 +' J_Prescriber_State__c, J_Prescriber_Zip__c, J_Primary_Dx_Code__c, J_Secondary_Dx_Code__c, J_SP_City__c, J_SP_Resta_Flg__c'
 +' FROM J_SP_Inbound__c where J_Import_Status__c=\'Created\'';
        return Database.getQueryLocator(query);
    }
    /**
 * @description This method is part of a batch process that processes the records from the `J_SP_Inbound__c` object
 *              and updates corresponding records in the `J_Order__c`, `J_SP_Status_Update__c`, and `CareProgramEnrollee` objects.
 *              It performs the following tasks:
 *              - Extracts relevant data from `J_SP_Inbound__c` records and maps it to `J_Order__c` and `J_SP_Status_Update__c` objects.
 *              - Creates or updates `J_Order__c` records based on the shipment data from `J_SP_Inbound__c`.
 *              - Creates or updates `J_SP_Status_Update__c` records for status tracking.
 *              - Sets the import status on `J_SP_Inbound__c` records based on the success or failure of the updates.
 *              - Updates the `Current_Dose_Record__c` field in `PatientMedicationDosage` if necessary.
 *
 * @param bc The context object for the batch job, which provides batch-specific information.
 * @param jSPList A list of `J_SP_Inbound__c` records to be processed in the current batch. Each record represents an inbound
 *                data entry that is either a shipment or status update.
 *
 * @throws Exception If there are errors during any DML operations, such as inserting or updating records, an exception
 *                   will be thrown to log and handle the error.
 *
 * This method handles the logic for processing shipment and status records, updating records in Salesforce,
 * and maintaining proper import status on the `J_SP_Inbound__c` records.
 */

     
    global WITH SHARING void execute(Database.BatchableContext bc, List<J_SP_Inbound__c> jSPList) {
        set<string> setShipmentRecords = new set<string>();
        set<string> setenrolleeID = new set<string>();
        map<string,id> mapPatientIDPatientMap = new map<string,id>();
        map<string,J_Order__c> mapOrderNameOrder = new map<string,J_Order__c>();
        List<J_Order__c> insertJOrder=new List<J_Order__c>();
        List<J_SP_Status_Update__c > insertDAStatus=new List<J_SP_Status_Update__c >();
        Set<Id> accPatientId = new Set<Id>();
        List<J_SP_Inbound__c> updateStatus=new List<J_SP_Inbound__c>();
      
        set<id> stagingStatusIDSet = new set<id>();
        set<id> setInboundDataForUpdate = new set<id>();
        String description = 'There is an update in the ';
        for(J_SP_Inbound__c jsp : jSPList) {
            setenrolleeID.add(jsp.Enrollee_ID__c); 
            if(jsp.J_Record_type__c == 'Shipment'){
                setShipmentRecords.add(jsp.J_SP_Unique_Id__c);
            }
        }
        for(J_Order__c ords : [Select id, Care_Program_Enrollee__c,Care_Program_Enrollee_Product__c,Unique_Record_ID__c,J_SP_Confirm_Order_Receipt_Date__c,RX_DATE__c,J_SP_Order_Number__c,J_Refills_Remaining__c,
                               J_NDC_Number__c,J_Quantity__c,Unit_Starting_Dose__c,Unit_Daily_Dose__c,J_Total_Daily_Dose_in_mg__c,J_Order_Ship_Date__c,Record_Entry_Date__c,
                               J_Dosage_Type__c,J_SP_Refill_Date__c,J_SP_Shipment_Type__c,J_Drug_Name__c,J_Ipsen_Order_Date__c,J_Fill__c,Order_Shipping_Tracking_Number__c,Care_Program_Enrollee__r.AccountId,J_DA_Inbound_Record_Id__c
                               From J_Order__c where Unique_Record_ID__c=:setShipmentRecords ]){
            if(!mapOrderNameOrder.containsKey(ords.Unique_Record_ID__c)) {
                mapOrderNameOrder.put(ords.Unique_Record_ID__c,ords);}
        }
        list<CareProgramEnrollee> cpEnrollee = [Select id, AccountId,Enrollee_ID__c,CC_Owner__c from CareProgramEnrollee where Enrollee_ID__c=:setenrolleeID];
        
        for(CareProgramEnrollee cpe : cpEnrollee){
            mapPatientIDPatientMap.put(cpe.Enrollee_ID__c,cpe.ID);
        }
        //map<string,Account> mapPatientIDPatientMap =new map<string,account> ([]);
        
        for(J_SP_Inbound__c jsp : jSPList) { 
            if(mapPatientIDPatientMap.get(jsp.Enrollee_ID__c)!=null)
            {
                if(jsp.J_Record_type__c == 'Shipment'){                    
                    J_Order__c jOrder =(mapOrderNameOrder.containsKey(jsp.J_SP_Unique_Id__c))?mapOrderNameOrder.get(jsp.J_SP_Unique_Id__c):new J_Order__c();
                    jOrder.Unique_Record_ID__c = jsp.J_SP_Unique_Id__c;
                    jOrder.Record_Entry_Date__c = jsp.J_Record_Entry_Date__c;
                    jOrder.RX_DATE__c = jsp.J_RX_DATE__c;                
                    jOrder.J_SP_Order_Number__c = jsp.J_RX_Num__C;
                    jOrder.SP_Name__c = jsp.J_SP_Name__c;
                    jOrder.RX_UOM__c = jsp.J_RX_UOM__c;
                    jOrder.J_Refills_Remaining__c = jsp.J_RX_Refil_Remaining__c;
                    jOrder.J_NDC_Number__c=jsp.J_RX_NDC__c;                
                    jOrder.J_Quantity__c = jsp.J_RX_Day_Supply__c;
                    if(jsp.J_RX_UOM__c!=null){
                        if(!string.isblank(jsp.J_RX_UOM__c) && (jsp.J_RX_UOM__c=='mg' || jsp.J_RX_UOM__c=='MG') ) {
                            jOrder.Unit_Starting_Dose__c = 'Milligram (mg)';
                             jOrder.Unit_Daily_Dose__c = 'Milligram (mg)';
                        } else if(!string.isblank(jsp.J_RX_UOM__c) && (jsp.J_RX_UOM__c=='ml' || jsp.J_RX_UOM__c=='ML') ) {
                            jOrder.Unit_Starting_Dose__c = 'Milliliter (ml)';
                            jOrder.Unit_Daily_Dose__c = 'Milliliter (ml)';
                        } else if(!string.isblank(jsp.J_RX_UOM__c) && (jsp.J_RX_UOM__c=='mcg' || jsp.J_RX_UOM__c=='MCG') ) {
                            jOrder.Unit_Starting_Dose__c = 'mcg';
                            jOrder.Unit_Daily_Dose__c = 'mcg';
                        } 
                        else {
                            jOrder.Unit_Starting_Dose__c =jsp.J_RX_UOM__c;
                            jOrder.Unit_Daily_Dose__c =jsp.J_RX_UOM__c;
                        }                    
                    }
                    
                    jOrder.J_Total_Daily_Dose_in_mg__c = String.valueOf(jsp.J_RX_Qty__c);
                    jOrder.J_Order_Ship_Date__c = jsp.J_RX_Ship_Date__c;
                    jOrder.J_Dosage_Type__c=jsp.J_RX_Dosage_Type__c;                
                    jOrder.J_SP_Refill_Date__c = jsp.J_RX_Refil_Date__c;                
                    jOrder.J_SP_Shipment_Type__c = jsp.J_RX_Shipment_Type__c;
                    
                    JC_Inbound_From_Hub_Product_Mapping__mdt drug = JC_Inbound_From_Hub_Product_Mapping__mdt.getInstance(jsp.J_Product_Name__c.replaceall(' ','_').toUpperCase());
                    //System.debug('Drug --> '+ drug);
                    
                    jOrder.J_Drug_Name__c = drug.JC_Drug_Name__c;                
                    jOrder.J_Ipsen_Order_Date__c = jsp.J_Record_Entry_Date__C;                
                    jOrder.J_Fill__c = jsp.J_RX_Fill__C;
                    jOrder.Order_Shipping_Tracking_Number__c = jsp.J_RX_Shipment_ID__C;
                    jOrder.Care_Program_Enrollee__c = mapPatientIDPatientMap.get(jsp.Enrollee_ID__c)==null?jsp.Enrollee_ID__c:mapPatientIDPatientMap.get(jsp.Enrollee_ID__c);
                    jOrder.J_DA_Inbound_Record_Id__c = jsp.Id;
                    
                    
                    insertJOrder.add(jOrder);
                    insertDAStatus.add(populateStatusFields(jsp, mapPatientIDPatientMap));
                    description = formatDescription(jsp);
                }
                else if(jsp.J_Record_type__c == 'Status'){
                    insertDAStatus.add(populateStatusFields(jsp, mapPatientIDPatientMap));
                    description = formatDescription(jsp);
                }
                accPatientId.add(mapPatientIDPatientMap.get(jsp.Enrollee_ID__c));
            } else {
                jsp.J_Import_Status__c = 'Failure';
                jsp.J_Error_Information__c = 'Invalid Erollee ID : ' +jsp.Enrollee_ID__c ;                
                updateStatus.add(jsp);
                stagingStatusIDSet.add(jsp.ID);
            }
        }
            
        Map<Id,Id> accOwnerIdMap = new Map<Id,Id>();
        for(CareProgramEnrollee acc: [Select Id, CC_Owner__c from CareProgramEnrollee WHERE ID IN:accPatientId ]){
            accOwnerIdMap.put(acc.Id,acc.CC_Owner__c);
        }
        
        if(!insertJOrder.isEmpty()){
            Integer i = 0;
            try
            {
                Database.upsertResult[] lsr = Database.upsert(insertJOrder,false);
                for (Database.upsertResult sr : lsr) {
                    if(!stagingStatusIDSet.contains(insertJOrder[i].J_DA_Inbound_Record_Id__c)){
                        if (!sr.isSuccess() ){//&& !setInboundDataForUpdate.contains(insertJOrder[i].J_DA_Inbound_Record_Id__c)){
                            String errMsg = sr.getErrors()[0].getMessage() + ' ' +sr.getErrors()[0].getFields();
                            J_SP_Inbound__c sp = new J_SP_Inbound__c();
                            sp.Id = insertJOrder[i].J_DA_Inbound_Record_Id__c;
                            sp.J_Import_Status__c = 'Failure';
                            sp.J_Error_Information__c = errMsg;
                            updateStatus.add(sp);
                            //System.debug('insertJOrder[i].J_DA_Inbound_Record_Id__c :'+ insertJOrder[i].J_DA_Inbound_Record_Id__c);
                            setInboundDataForUpdate.add(insertJOrder[i].J_DA_Inbound_Record_Id__c);
                        }
                        else{
                            //if(!setInboundDataForUpdate.contains(insertJOrder[i].J_DA_Inbound_Record_Id__c)){
                            J_SP_Inbound__c sp = new J_SP_Inbound__c();
                            sp.Id = insertJOrder[i].J_DA_Inbound_Record_Id__c;
                            sp.J_Import_Status__c = 'Successful';
                            sp.J_Error_Information__c = '';
                            updateStatus.add(sp);
                            //System.debug('Else insertJOrder[i].J_DA_Inbound_Record_Id__c :' + insertJOrder[i].J_DA_Inbound_Record_Id__c);
                            setInboundDataForUpdate.add(insertJOrder[i].J_DA_Inbound_Record_Id__c);
                            //}
                        }
                        stagingStatusIDSet.add(insertJOrder[i].J_DA_Inbound_Record_Id__c);
                        i++;
                    }
                }
            }
            
            catch(exception ex){
            GenericLogger.exceptionLog('SPInboundBatchclass Error in Upsert : ---------:'+ ex);
            }
        }

        if(!insertDAStatus.isEmpty()){
            Integer i = 0;
            Database.SaveResult[] lsr = Database.insert(insertDAStatus,false);
            for (Database.SaveResult sr : lsr) {
                if (!sr.isSuccess() && i<=insertDAStatus.size()-1 && !stagingStatusIDSet.contains(insertDAStatus[i].J_DA_Inbound_Record_Id__c)){
                    String errMsg = sr.getErrors()[0].getMessage();
                    J_SP_Inbound__c sp = new J_SP_Inbound__c();
                    sp.Id = insertDAStatus[i].J_DA_Inbound_Record_Id__c;
                    sp.J_Import_Status__c = 'Failure';
                    sp.J_Error_Information__c = errMsg;
                    updateStatus.add(sp);
                    //System.debug('insertDAStatus[i].J_DA_Inbound_Record_Id__c :' + insertDAStatus[i].J_DA_Inbound_Record_Id__c);
                    
                stagingStatusIDSet.add(insertDAStatus[i].J_DA_Inbound_Record_Id__c);
                }
                else if(sr.isSuccess()) {
                    if(i<=insertDAStatus.size()-1  && !stagingStatusIDSet.contains(insertDAStatus[i].J_DA_Inbound_Record_Id__c)){
                        J_SP_Inbound__c sp = new J_SP_Inbound__c();
                        sp.Id = insertDAStatus[i].J_DA_Inbound_Record_Id__c;
                        sp.J_Import_Status__c = 'Successful';
                         sp.J_Error_Information__c = '';
                        updateStatus.add(sp);
                        stagingStatusIDSet.add(insertDAStatus[i].J_DA_Inbound_Record_Id__c);
                    }
                }                
                i++;
            }
        } 
        
        if(!updateStatus.isEmpty()){
            for(J_SP_Inbound__c status: updateStatus){
            GenericLogger.debugLog('status : ' + status);
            }
            update updateStatus;
        }
        if(!insertJOrder.isEmpty()){
            updateCurrentDosing(insertJOrder);
        }
    }   
    
    @TestVisible
    private static J_SP_Status_Update__c populateStatusFields(J_SP_Inbound__c jsp, map<string,id> mapPatientIDPatientMap){
        J_SP_Status_Update__c spStatus = new J_SP_Status_Update__c();
        spStatus.Record_Entry_Date__c = jsp.J_Record_Entry_Date__C;
        spStatus.J_Case_Number__c =jsp.J_SR__c;
        spStatus.J_Program__c =jsp.J_Program_Name__c; 
        spStatus.J_Status_Date__c = jsp.J_Status_Date__c; 
        spStatus.J_SP_Status__c =jsp.J_Status__c;
        spStatus.J_SubStatus__c =jsp.J_Sub_Status__c;                
        spStatus.J_SP_Journey_Patient_Id__c = mapPatientIDPatientMap.get(jsp.Enrollee_ID__c)==null?jsp.Enrollee_ID__c:mapPatientIDPatientMap.get(jsp.Enrollee_ID__c);
        spStatus.Care_Program_Enrollee__c = mapPatientIDPatientMap.get(jsp.Enrollee_ID__c)==null?jsp.Enrollee_ID__c:mapPatientIDPatientMap.get(jsp.Enrollee_ID__c);
        spStatus.J_SP_Patient_ID__c =jsp.J_SP_Patient_Id__C;                
        spStatus.J_SP_Hub_Patient_Id__c = jsp.J_HUB_Patient_ID__c;                
        spStatus.J_Patient_Gender__c = jsp.J_Patient_Gender__c;                
        spStatus.J_Patient_State__c = jsp.J_Patient_State__c;                
        spStatus.J_Primary_Dx_Code__c = jsp.J_Primary_Dx_Code__c;
        spStatus.J_Secondary_Dx_Code__c = jsp.J_Secondary_Dx_Code__c;                
        spStatus.J_Concurrent_Txt__c = jsp.J_Concurrent_Txt__c;                
        spStatus.J_SP_HCP_Last_Name__c = jsp.J_HCP_LastName__c;                
        spStatus.J_SP_HCP_First_Name__c = jsp.J_HCP_FirstName__c;                                
        spStatus.J_Practice_Location__c = jsp.J_HCP_Location__c;                
        spStatus.J_Prescriber_Address_1__c = jsp.J_Prescriber_Address_1__c;
        spStatus.J_Prescriber_Address_2__c = jsp.J_Prescriber_Address_2__c;
        spStatus.J_Prescriber_City__c = jsp.J_Prescriber_City__c;
        spStatus.J_Prescriber_State__c = jsp.J_Prescriber_State__c;
        spStatus.J_Prescriber_Zip__c = jsp.J_Prescriber_Zip__c;
        spStatus.J_Prescriber_Phone__c = jsp.J_Prescriber_Phone__c;
        spStatus.J_Prescriber_Fax__c = jsp.J_Prescriber_Fax__c;                
        spStatus.J_SP_HCP_NPI__c = jsp.J_HCP_NPI__c;                
        spStatus.J_Prescriber_DEA__c = jsp.J_Prescriber_DEA__c;                
        spStatus.J_SP_Prior_Authorization_Required__c = jsp.J_PA_Req__c;
        spStatus.J_SP_EffectiveFrom__c = jsp.J_PA_Date__c;
        spStatus.J_PA_Appeal_Date__c = jsp.J_PA_Appeal_Date__c;                
        spStatus.J_SP_EffectiveTo__c = jsp.J_PA_Exp_Date__c;
        spStatus.J_Co_Insurance_Percent__c = jsp.J_Claim_Co_Ins_percent__c;
        spStatus.J_Co_Insurance_Amt__c = jsp.J_Claim_Co_Ins_Amt__c;
        spStatus.J_Co_Pay_Amount__c = jsp.J_Claim_CoPay_Amount__c;  
        if(jsp.J_Claim_CoPay_Elg__c=='Y' ||jsp.J_Claim_CoPay_Elg__c=='y' ){
            spStatus.J_Co_pay_card_eligible__c =true;
        } else if(jsp.J_Claim_CoPay_Elg__c=='N' ||jsp.J_Claim_CoPay_Elg__c=='n' ){
            spStatus.J_Co_pay_card_eligible__c =false;
        } 
        if(jsp.J_Claim_CoPay_Applied__c=='Y' ||jsp.J_Claim_CoPay_Applied__c=='y' ){
            spStatus.J_Co_Pay_Card_Applied__c =true;
        } else if(jsp.J_Claim_CoPay_Applied__c=='N' ||jsp.J_Claim_CoPay_Applied__c=='n' ){
            spStatus.J_Co_Pay_Card_Applied__c =false;
        } 
        //spStatus.J_Co_pay_card_eligible__c = boolean.valueof(jsp.J_Claim_CoPay_Elg__c);         
        //spStatus.J_Co_Pay_Card_Applied__c = boolean.valueof(jsp.J_Claim_CoPay_Applied__c);       
        spStatus.J_CopayAssistAmount__c = jsp.J_Claim_CoPay_Asst_Amt__c;                             
        spStatus.J_Total_Patient_payment__c = jsp.J_Claim_Pt_Paid_Amt__c;
        if(jsp.J_Claim_OOP_Met__c=='Y' ||jsp.J_Claim_OOP_Met__c=='y' ){
            spStatus.J_pat_OOPMet__c =true;
        } else if(jsp.J_Claim_OOP_Met__c=='N' ||jsp.J_Claim_OOP_Met__c=='n' ){
            spStatus.J_pat_OOPMet__c =false;
        }    
        spStatus.J_PlanPaidAmt__c = jsp.J_Claim_PPayer_Paid_Amt__c;   
        spStatus.J_Claim_Type__c = jsp.J_Claim_Type__c;                
        spStatus.J_SP_PP_Insurance_Type__c = jsp.J_INS_PP_Type__c;
        spStatus.J_SP_PP_GroupNumber__c = jsp.J_INS_PP_Group_ID__c;
        spStatus.J_SP_PP_Payer_Id__c = jsp.J_INS_PP_ID__c;
        spStatus.J_SP_RxBin_Number__c = jsp.J_INS_PP_BIN__c;                
        spStatus.J_Primary_Payer_PCN__c = jsp.J_INS_PP_PCN__c;                
        spStatus.J_SP_INS_PP_Name__c = jsp.J_INS_PP_Name__c;                
        spStatus.J_SP_PP_GroupPlanNumber__c = jsp.J_INS_PP_Plan_Name__c;
        spStatus.J_SP_PP_PBM_Policy_Numb__c = jsp.J_INS_PP_PBM__c;
        spStatus.J_SP_Sec_Insurance_Type__c = jsp.J_INS_SecP_Type__c;
        spStatus.J_SP_Sec_Payer_Id__c = jsp.J_INS_SecP_ID__c;                
        spStatus.J_Secondary_Payer_BIN__c = jsp.J_INS_SecP_BIN__c;          
        spStatus.J_Secondary_Payer_PCN__c = jsp.J_INS_SecP_PCN__c;                
        spStatus.J_SP_INS_Sec_Name__c = jsp.J_INS_SecP_Name__c;                
        spStatus.J_SP_INS_Sec_State__c = jsp.J_INS_SecP_State__c;                
        spStatus.J_SP_Sec_Group_Number__c = jsp.J_INS_SecP_Group_ID__c;
        spStatus.J_SP_Sec_GroupPlanNumber__c = jsp.J_INS_SecP_Plan_Name__c;
        spStatus.J_SP_Name__c = jsp.J_SP_Name__c;                
        spStatus.J_SP_City__c = jsp.J_SP_City__c;                             
        spStatus.J_Location_NCPDP__c = jsp.J_SP_Loc_NCPDP__c;
        if(jsp.J_SP_Resta_Flg__c=='Y' ||jsp.J_SP_Resta_Flg__c=='y' ){
            spStatus.J_SP_Resta_Flg__c =true;
        } else if(jsp.J_SP_Resta_Flg__c=='N' ||jsp.J_SP_Resta_Flg__c=='n' ){
            spStatus.J_SP_Resta_Flg__c =false;
        }  
        //spStatus.J_SP_Resta_Flg__c = jsp.J_SP_Resta_Flg__c;                
        spStatus.J_Unique_Record_ID__c = jsp.J_SP_Unique_Id__c;
        spStatus.J_DA_Inbound_Record_Id__c = jsp.Id;
        return spStatus;
        
    }
    
    @TestVisible
    private static string formatDescription(J_SP_Inbound__c jsp){
        string description='';
        if(jsp.Enrollee_ID__c!='' || jsp.J_HUB_Patient_ID__c !='' || jsp.J_HCP_FirstName__c !='' || jsp.J_HCP_LastName__c !='')
        {
            description = description +'Patient Demographics section ';
        }
        if(jsp.J_INS_PP_Type__c!='' || jsp.J_INS_PP_Group_ID__c !='' || jsp.J_INS_PP_ID__c !='' || jsp.J_INS_PP_Name__c !='' || jsp.J_INS_PP_Plan_Name__c !='' || jsp.J_INS_PP_PBM__c !='' ||
           jsp.J_INS_SecP_Type__c !='' || jsp.J_INS_SecP_ID__c !='' || jsp.J_INS_SecP_Name__c!='' || jsp.J_INS_SecP_State__c!='' ||jsp.J_INS_SecP_Group_ID__c !='' || jsp.J_INS_SecP_Plan_Name__c !='' || jsp.J_INS_PP_BIN__c !='')
        {
            description = description.contains('Patient Demographics')? description +', Insurance Plan section ':description+'Insurance Plan section';
        }
        if(jsp.J_PA_Req__c !='' || jsp.J_PA_Date__c !=null || jsp.J_PA_Exp_Date__c !=null)
        {
            description = description.contains('Patient Demographics') || description.contains('Insurance Plan') ? description +'and Prior Auth Details section.':description+'Prior Auth Details section.';
        }else{
            description = description +'';
        }
        return description;
    }
    /**
 * @description Updates the `Current_Dose_Record__c` field of `PatientMedicationDosage` records based on the
 *              relationship between `J_Order__c` and `PatientMedicationDosage` objects. This method determines
 *              whether a dose is current based on matching medication dosage and NDC code.
 *
 * @param newOrder List of `J_Order__c` records to process.
 *
 * The method performs the following:
 * - Extracts Enrollee IDs and order IDs from the provided list of `J_Order__c` records.
 * - Queries the `J_Order__c` records to map their `Patient_Medication_Dosage__c` values to `J_NDC_Number__c`.
 * - Queries `PatientMedicationDosage` records for the given Enrollee IDs.
 * - Updates the `Current_Dose_Record__c` field of `PatientMedicationDosage` based on whether the `Patient_Medication_Dosage__c`
 *   from the order matches with an existing dosage record.
 * - Updates the modified `PatientMedicationDosage` records in the database.
 */

    public static void updateCurrentDosing(List<J_Order__c> newOrder){
        set<id> enrolleeID = new Set<id>();
        set<id> orderID = new Set<id>();
        Map<id,string> mapOrderPMD = new Map<id,string>();
        for(J_Order__c o:newOrder){
            enrolleeID.add(o.Care_Program_Enrollee__c);
            orderID.add(o.id);
        }
        list<J_Order__c> order = new list<J_Order__c>([select id,Care_Program_Enrollee__c,Patient_Medication_Dosage__c,J_NDC_Number__c from J_Order__c where id in:orderID]);
        for(J_Order__c o:order){
            mapOrderPMD.put(o.Patient_Medication_Dosage__c,o.J_NDC_Number__c);
        }
       
        list<PatientMedicationDosage> dose = new list<PatientMedicationDosage>([select id,Care_Program_Enrollee_Name__c,Care_Program_Enrollee_Product__c,Current_Dose_Record__c,NDC_Code__c from PatientMedicationDosage where Care_Program_Enrollee_Name__c in:enrolleeID]);
        for(PatientMedicationDosage pmd:dose){
            if(mapOrderPMD.containsKey(pmd.id)){
                pmd.Current_Dose_Record__c= true;
            }
            else{
                pmd.Current_Dose_Record__c= false;
            }
           
        }
        update dose;
    }
    /**
 * @description This method is called after all batches have been processed. It is part of the Database.Batchable
 *              interface and is used to handle any final operations after the batch processing is complete.
 *
 * @param bc The context object for the batch job, which can be used to access batch-specific information.
 *
 * This method logs a message indicating the successful completion of the batch job.
 */

    global void finish(Database.BatchableContext bc) {
        GenericLogger.debugLog('***JourneySPInboundBatchClass processed successfully***');
    }
}