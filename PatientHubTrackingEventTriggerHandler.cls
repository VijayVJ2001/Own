/**
* @description       : 
* @author            : Ipsen
* @group             : 
* @last modified on  : 08-12-2023
**/
public without sharing class PatientHubTrackingEventTriggerHandler {
    public static List<T_Hub_Tracking__c> hubTrackings = new List<T_Hub_Tracking__c>();
    public static List<String> sourceObjectNames = new List<String>{'Account','Case','CareProgramEnrollee','MemberPlan','J_Copay__c','J_Charitable__c','CarePreauth','PatientMedicationDosage','CareProgramProduct'};
        public static List<String> sourceObjectNamesForMultipleRecords = new List<String>{'J_Referral__c','PatientMedicationDosage'};
        /**
 * @description Processes a list of Patient_Hub_Tracking_Event__e platform events to 
 *              create and insert Hub Tracking records.
 *
 * This method iterates through each event in the provided list and performs 
 * necessary actions, such as populating Hub Tracking records based on the 
 * enrollee and patient IDs. Once all required Hub Tracking records are 
 * prepared, they are inserted into the database. Any exceptions encountered 
 * during execution are logged using the GenericLogger utility.
 *
 * @param events The list of Patient_Hub_Tracking_Event__e platform events to be processed.
 */   
        public static void process(List<Patient_Hub_Tracking_Event__e> events){
                try{
                    // Iterate through each notification.
                    for (Patient_Hub_Tracking_Event__e event : events) {
                        populateHubTracking(event.Enrollee_Id__c, event.Patient_Id__c);
                    }
                    if(hubTrackings.size()>0){
                        if (Schema.sObjectType.T_Hub_Tracking__c.isCreateable()) {
                            insert hubTrackings; 
                        } else {
                            GenericLogger.debugLog('User does not have permission to create T_Hub_Tracking__c records.');
                        }
                    }
                }
                catch(Exception e){
                    GenericLogger.exceptionLog(e);
                }
            }
   /**
 * @description Populates and prepares a T_Hub_Tracking__c record with data derived 
 *              from various related objects based on the given enrollee and patient IDs.
 *
 * This method queries related objects and fields, maps data using metadata mappings, 
 * and sets specific field values for the T_Hub_Tracking__c record. It handles 
 * conditions such as primary/secondary roles, consent statuses, and benefit types, 
 * ensuring the record is populated accurately based on business rules. 
 * The populated record is added to the `hubTrackings` list and further processing 
 * is initiated by calling `createMultipleRecords`.
 *
 * @param enrolleeId The ID of the CareProgramEnrollee record used to fetch related data.
 * @param patientId  The ID of the Patient record used to fetch related data.
 */ 
public static void populateHubTracking(String enrolleeId, String patientId) {
    Id carePlanRecordTypeId = getCarePlanRecordTypeId();
    
    T_Hub_Tracking__c hubTracking = initializeHubTracking();
    
    // Populate hubTracking fields from CareProgramEnrollee and CareProgramProduct
    populateCareProgramFields(enrolleeId, hubTracking);
    
    // Process each source object for mapping and populate hubTracking accordingly
    for (String sourceObjectName : sourceObjectNames) {
        List<Hub_Tracking_Field_Mapping__mdt> hubTrackingMappings = getHubTrackingMappings(sourceObjectName);
        SObject[] sourceObjectRecords = querySourceObject(enrolleeId, patientId, sourceObjectName, hubTrackingMappings);
        populateFieldsFromSourceObjects(sourceObjectRecords, hubTracking, hubTrackingMappings, sourceObjectName);
    }
    
    // Handle consents and authorization form
    handleConsents(enrolleeId, hubTracking);
    
    // Handle diseases for the case
    handleDisease(enrolleeId, carePlanRecordTypeId, hubTracking);
    
    // Handle coverage benefits and preauthorizations
    handleCoverageBenefits(enrolleeId, hubTracking);
    
    // Handle charitable program data
    handleCharitableProgram(enrolleeId, hubTracking);

    // Finalize any remaining fields
    finalizeHubTrackingFields(hubTracking);

    // Perform any final operations (e.g., insert/update)
    // insert or update hubTracking as needed
}

private static Id getCarePlanRecordTypeId() {
    return [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND Name = 'CarePlan' LIMIT 1].Id;
}

private static T_Hub_Tracking__c initializeHubTracking() {
    T_Hub_Tracking__c hubTracking = new T_Hub_Tracking__c();
    hubTracking.PHI_Consent__c = 'N';
    hubTracking.HIPPA_Consent__c = 'N';
    hubTracking.Referral_Source__c = 'HUB';
    hubTracking.RX_Recieved__c = 'N';
    hubTracking.Primary_Prior_Authorization_Required__c = 'N';
    return hubTracking;
}

private static void populateCareProgramFields(String enrolleeId, T_Hub_Tracking__c hubTracking) {
    CareProgramEnrollee enrollee = [SELECT Id, HCP_Lead__c, HCP_Lead__r.Lead_ID__c, Lead.Lead_ID__c, LeadId, Status, Sub_Status__c, CareProgramId 
                                    FROM CareProgramEnrollee WHERE Id = :enrolleeId WITH SECURITY_ENFORCED];
    
    for (CareProgramProduct cpprod : [SELECT Id, Product.Name, CareProgramId 
                                      FROM CareProgramProduct WHERE CareProgramId = :enrollee.CareProgramId WITH SECURITY_ENFORCED LIMIT 1]) {
        hubTracking.Brand_Name__c = cpprod.Product.Name;
    }
}

private static List<Hub_Tracking_Field_Mapping__mdt> getHubTrackingMappings(String sourceObjectName) {
    return [SELECT Id, SourceField__c, Target_Object__r.QualifiedAPIName, Target_Field__r.QualifiedAPIName 
            FROM Hub_Tracking_Field_Mapping__mdt 
            WHERE Source_Object__r.QualifiedAPIName = :sourceObjectName WITH SECURITY_ENFORCED];
}

private static void populateFieldsFromSourceObjects(SObject[] sourceObjectRecords, T_Hub_Tracking__c hubTracking, 
                                                     List<Hub_Tracking_Field_Mapping__mdt> hubTrackingMappings, String sourceObjectName) {
    for (SObject sourceObject : sourceObjectRecords) {
        for (Hub_Tracking_Field_Mapping__mdt mapping : hubTrackingMappings) {
            String fieldValue = getFieldValue(sourceObject, mapping.SourceField__c);
            if (shouldPopulateField(sourceObjectName, sourceObject, mapping)) {
                hubTracking.put(mapping.Target_Field__r.QualifiedAPIName, fieldValue);
            }
        }
    }
}

private static Boolean shouldPopulateField(String sourceObjectName, SObject sourceObject, Hub_Tracking_Field_Mapping__mdt mapping) {
    if (sourceObjectName == 'MemberPlan') {
        return (sourceObject.get('J_Role__c') == 'Primary' && mapping.Target_Field__r.QualifiedAPIName.containsIgnoreCase('Primary')) ||
               (sourceObject.get('J_Role__c') == 'Secondary' && mapping.Target_Field__r.QualifiedAPIName.containsIgnoreCase('Secondary'));
    } else if (sourceObjectName == 'J_Charitable__c') {
        return (sourceObject.get('J_CharitableProgramType__c') == 'TPAP' && mapping.Target_Field__r.QualifiedAPIName.containsIgnoreCase('TPAP')) ||
               (sourceObject.get('J_CharitableProgramType__c') != 'TPAP' && !mapping.Target_Field__r.QualifiedAPIName.containsIgnoreCase('TPAP'));
    } else {
        return true;
    }
}

private static void handleConsents(String enrolleeId, T_Hub_Tracking__c hubTracking) {
    for (AuthorizationFormConsent consent : [SELECT Id, J_ConsentExpirationDate__c, J_ConsentStatus__c, Signatured_Date_PHI__c 
                                             FROM AuthorizationFormConsent WHERE Care_Program_Enrollee__c = :enrolleeId 
                                             AND J_TypeOfConsent__c = 'Patient Authorization' WITH SECURITY_ENFORCED]) {
        hubTracking.Consent_Expiration_Date__c = String.valueOf(consent.J_ConsentExpirationDate__c)?.replaceAll('-', '');
        if (consent.J_ConsentStatus__c == 'Active') {
            hubTracking.PHI_Consent__c = 'Y';
            hubTracking.HIPPA_Consent__c = 'Y';
            hubTracking.HIPPA_Consent_Date__c = String.valueOf(consent.J_ConsentExpirationDate__c)?.replaceAll('-', '');
        }
    }
}

private static void handleDisease(String enrolleeId, Id carePlanRecordTypeId, T_Hub_Tracking__c hubTracking) {
    for (Case tp : [SELECT Id, Disease__c FROM Case WHERE Care_Program_Enrollee__c = :enrolleeId 
                    AND RecordTypeId = :carePlanRecordTypeId WITH SECURITY_ENFORCED]) {
        hubTracking.Indication__c = (tp.Disease__c == 'Fibrodysplasia Ossificans Progressiva (FOP)') ? 'FOP' : tp.Disease__c;
    }
}

private static void handleCoverageBenefits(String enrolleeId, T_Hub_Tracking__c hubTracking) {
    for (CoverageBenefit coverageBenefit : [SELECT Id, J_PriorAuthorizationRequired__c, J_BenefitType__c, MemberPlan.Status, 
                                             MemberPlan.J_Role__c, J_CoPay__c, J_OOPMax__c 
                                             FROM CoverageBenefit WHERE Care_Program_Enrollee__c = :enrolleeId 
                                             AND J_CoverageBenefitStatus__c = 'Active' WITH SECURITY_ENFORCED LIMIT 3]) {
        if (coverageBenefit.MemberPlan.Status == 'Active') {
            if (coverageBenefit.MemberPlan.J_Role__c == 'Primary') {
                hubTracking.Primary_Prior_Authorization_Required__c = (coverageBenefit.J_PriorAuthorizationRequired__c == 'Yes') ? 'Y' : 'N';
                hubTracking.PRIMARY_BENEFIT_TYPE__c = coverageBenefit.J_BenefitType__c;
                hubTracking.PRIMARY_COPAY_AMOUNT__c = coverageBenefit.J_CoPay__c;
                hubTracking.FINAL_PATIENT_OUT_OF_POCKET_COST__c = coverageBenefit.J_OOPMax__c;
            }
            if (coverageBenefit.MemberPlan.J_Role__c == 'Secondary') {
                hubTracking.SECONDARY_BENEFIT_TYPE__c = coverageBenefit.J_BenefitType__c;
                hubTracking.SECONDARY_CO_PAY_AMOUNT__c = coverageBenefit.J_CoPay__c;
            }
        }

        for (CarePreauth priAuth : [SELECT Id, Status, J_AuthorizationEndDate__c, MemberPlan.J_Role__c 
                                    FROM CarePreauth WHERE J_CoverageBenefit__c = :coverageBenefit.Id 
                                    AND Status = 'Active' WITH SECURITY_ENFORCED LIMIT 1]) {
            if (priAuth.MemberPlan.J_Role__c == 'Primary') {
                hubTracking.PA_Status__c = priAuth.Status;
                hubTracking.PRIMARY_PA_EXPIRATION_DATE__c = priAuth.J_AuthorizationEndDate__c;
            }
        }
    }
}

private static void handleCharitableProgram(String enrolleeId, T_Hub_Tracking__c hubTracking) {
    for (J_Charitable__c papTpap : [SELECT Id, J_CharitableProgramType__c, J_Enrollment_End_Date__c 
                                    FROM J_Charitable__c WHERE Care_Program_Enrollee__c = :enrolleeId 
                                    AND J_CharitableStatus__c = 'Active' WITH SECURITY_ENFORCED LIMIT 1]) {
        if (papTpap.J_CharitableProgramType__c == 'TPAP') {
            hubTracking.TPAP_Expiration_Date__c = String.valueOf(papTpap.J_Enrollment_End_Date__c)?.replaceAll('-', '');
        }
    }
}

private static void finalizeHubTrackingFields(T_Hub_Tracking__c hubTracking) {
    if (String.isBlank(hubTracking.Patient_State__c)) {
        hubTracking.Patient_State__c = 'NA';
    }
    if (String.isBlank(hubTracking.Referral_Source__c)) {
        hubTracking.Referral_Source__c = 'HUB';
    }

        
        
        hubTrackings.add(hubTracking);
        createMultipleRecords(enrolleeId, patientId);
    }
    
    private static void createMultipleRecords(String enrolleeId, String patientId){
        
        
        List<Hub_Tracking_Field_Mapping__mdt>   hubTrackingMappingsForReferral = [SELECT Id,SourceField__c,Target_Object__r.QualifiedAPIName,Target_Field__r.QualifiedAPIName from Hub_Tracking_Field_Mapping__mdt where Source_Object__r.QualifiedAPIName='J_Referral__c'  WITH SECURITY_ENFORCED];
        Map<String, SObject> ndcToReferralMap = new Map<String, SObject>();
        for(SObject referralRecord : querySourceObject(enrolleeId, patientId, 'J_Referral__c', hubTrackingMappingsForReferral)){
            ndcToReferralMap.put(getFieldValue(referralRecord,'NDC_Code__c'), referralRecord);
        }
        
        List<Hub_Tracking_Field_Mapping__mdt>   hubTrackingMappingsForOrder = [SELECT Id,SourceField__c,Target_Object__r.QualifiedAPIName,Target_Field__r.QualifiedAPIName from Hub_Tracking_Field_Mapping__mdt where Source_Object__r.QualifiedAPIName='J_Order__c' WITH SECURITY_ENFORCED ];
        Map<String, SObject> medicationDosageIdToOrderMap = new Map<String, SObject>();
        for(SObject orderRecord : querySourceObject(enrolleeId, patientId, 'J_Order__c', hubTrackingMappingsForOrder)){
            medicationDosageIdToOrderMap.put(getFieldValue(orderRecord,'Patient_Medication_Dosage__c'), orderRecord);
        }
        
        List<Hub_Tracking_Field_Mapping__mdt>   hubTrackingMappingsForPatientMedication = [SELECT Id,SourceField__c,Target_Object__r.QualifiedAPIName,Target_Field__r.QualifiedAPIName from Hub_Tracking_Field_Mapping__mdt where Source_Object__r.QualifiedAPIName='PatientMedicationDosage' WITH SECURITY_ENFORCED ];
        SObject[] patientMedicationDosageRecords = querySourceObject(enrolleeId, patientId, 'PatientMedicationDosage', hubTrackingMappingsForPatientMedication);
        List<T_Hub_Tracking__c> hubTrackingList = new List<T_Hub_Tracking__c>(hubTrackings); 
        for(T_Hub_Tracking__c populatedHubTracking : hubTrackingList){
            Integer count = 1;

            
            for(SObject sourceObject : patientMedicationDosageRecords)
            {              
                T_Hub_Tracking__c hubTracking = new T_Hub_Tracking__c();  
                
                String ndcCode;
                String medicationDosageId = getFieldValue(sourceObject,'Id');
                if(count == 1){
                    hubTracking = populatedHubTracking;
                }else{
                    hubTracking = populatedHubTracking.clone(false, true, false, false);
                }
                
                for(Hub_Tracking_Field_Mapping__mdt hubTrackingmapping: hubTrackingMappingsForOrder){
                    hubTracking.put(hubTrackingmapping.Target_Field__r.QualifiedAPIName, '');
                    
                }
                for(Hub_Tracking_Field_Mapping__mdt hubTrackingmapping: hubTrackingMappingsForReferral){
                    hubTracking.put(hubTrackingmapping.Target_Field__r.QualifiedAPIName, '');
                    
                }
                
                for(Hub_Tracking_Field_Mapping__mdt hubTrackingmapping: hubTrackingMappingsForPatientMedication){
                    String fieldValue = getFieldValue(sourceObject,hubTrackingmapping.SourceField__c);
                    hubTracking.put(hubTrackingmapping.Target_Field__r.QualifiedAPIName, fieldValue);
                    
                    if(hubTrackingmapping.SourceField__c == 'NDC_Code__c'){
                        ndcCode = fieldValue;
                    }
                    
                }
                
                if(String.isNotBlank(ndcCode) && ndcToReferralMap.containsKey(ndcCode)){
                    SObject referral = ndcToReferralMap.get(ndcCode);
                    
                    for(Hub_Tracking_Field_Mapping__mdt hubTrackingmapping: hubTrackingMappingsForReferral){
                        hubTracking.put(hubTrackingmapping.Target_Field__r.QualifiedAPIName, getFieldValue(referral,hubTrackingmapping.SourceField__c));
                    }
                }
                
                if(String.isNotBlank(medicationDosageId) && medicationDosageIdToOrderMap.containsKey(medicationDosageId)){
                    SObject order = medicationDosageIdToOrderMap.get(medicationDosageId);
                    
                    for(Hub_Tracking_Field_Mapping__mdt hubTrackingmapping: hubTrackingMappingsForOrder){
                        hubTracking.put(hubTrackingmapping.Target_Field__r.QualifiedAPIName, getFieldValue(order,hubTrackingmapping.SourceField__c));
                        hubTracking.RX_Recieved__c  = 'Y';
                    }
                    
                }
                else{
                    hubTracking.RX_Recieved__c = 'N';
                }
                
                if(count > 1){
                    
                    hubTrackings.add(hubTracking);
                }
                
                count++;
            }
        }
        
    }
    
    
    
    private static SObject[] querySourceObject(String sourceObjectName, List<Hub_Tracking_Field_Mapping__mdt> hubTrackingMappings) {
        // Build SELECT clause
        String query = buildSelectClause(sourceObjectName, hubTrackingMappings);
    
        // Add WHERE clause based on object name
        query += buildWhereClause(sourceObjectName);
    
        // Add ORDER BY CreatedDate ASC
        query += ' ORDER BY CreatedDate ASC';
    
        // Log the query for debugging purposes
        GenericLogger.debugLog(query);
    
        // Execute the query
        return Database.query(query);
    }
    
    // Helper method to build SELECT clause
    private static String buildSelectClause(String sourceObjectName, List<Hub_Tracking_Field_Mapping__mdt> hubTrackingMappings) {
        StringBuilder queryBuilder = new StringBuilder('SELECT Id');
    
        // Add source fields
        Set<String> sourceFields = new Set<String>();
        for (Hub_Tracking_Field_Mapping__mdt mapping : hubTrackingMappings) {
            if (mapping.SourceField__c != 'Id') {
                sourceFields.add(mapping.SourceField__c);
            }
        }
        for (String sourceField : sourceFields) {
            queryBuilder.append(', ').append(sourceField);
        }
    
        // Add specific fields for certain objects
        Map<String, String> additionalFields = new Map<String, String>{
            'MemberPlan' => ', J_Role__c',
            'J_Charitable__c' => ', J_CharitableProgramType__c',
            'J_Referral__c' => ', NDC_Code__c',
            'J_Order__c' => ', Patient_Medication_Dosage__c',
            'PatientMedicationDosage' => ', Unit_Daily_Dose__c, Patients_Current_Prescribed_Dose__c'
        };
    
        if (additionalFields.containsKey(sourceObjectName)) {
            queryBuilder.append(additionalFields.get(sourceObjectName));
        }
    
        return queryBuilder.toString();
    }
    
    // Helper method to build WHERE clause
    private static String buildWhereClause(String sourceObjectName) {
        Map<String, String> whereClauses = new Map<String, String>{
            'CareProgramEnrollee' => ' WHERE Id =:enrolleeId',
            'Account' => ' WHERE Id =:patientId',
            'J_Referral__c' => ' WHERE Care_Program_Enrollee__c =:enrolleeId AND Status__c =\'Active\'',
            'MemberPlan' => ' WHERE MemberId =:patientId AND Status =\'Active\'',
            'J_Copay__c' => ' WHERE Care_Program_Enrollee__c =:enrolleeId AND J_CurrentCopayStatus__c =\'Active\'',
            'J_Charitable__c' => ' WHERE Care_Program_Enrollee__c =:enrolleeId',
            'J_Order__c' => ' WHERE Care_Program_Enrollee__c =:enrolleeId',
            'PatientMedicationDosage' => ' WHERE Care_Program_Enrollee_Name__c =:enrolleeId AND Current_Dose_Record__c = True',
            'CarePreauth' => ' WHERE Care_Program_Enrollee__c =:enrolleeId AND Status =\'Active\'',
            'CoverageBenefit' => ' WHERE Care_Program_Enrollee__c =:enrolleeId',
            'Case' => ' WHERE Care_Program_Enrollee__c =:enrolleeId'
        };
    
        return whereClauses.containsKey(sourceObjectName) ? whereClauses.get(sourceObjectName) : '';
    }
    
    
    private static String getFieldValue(SObject obj, String inputFieldName){
        Object fieldValue;
        if(inputFieldName.contains('.')){
            String objectName = inputFieldName.substringBefore('.');
            String fieldName = inputFieldName.substringAfter('.');
            fieldValue = obj.getSobject(objectName)?.get(fieldName);
        }
        else{
            fieldValue = obj.get(inputFieldName);
        }
        
        if(inputFieldName.containsIgnoreCase('date')){
            Date dateValue = Date.valueOf(fieldValue);
            return String.valueOf(dateValue)?.replaceAll('-','');
        }
        
        else{
            return String.valueOf(fieldValue);
        }
    }
   /**
 * @description Publishes platform events of type Patient_Hub_Tracking_Event__e 
 *              for a list of CareProgramEnrollee records.
 *
 * This method creates and publishes Patient_Hub_Tracking_Event__e events 
 * using the provided list of CareProgramEnrollee records. Each event includes 
 * the enrollee ID and the associated patient ID. After publishing, it inspects 
 * the result for each event and logs success or error details using the 
 * GenericLogger utility.
 *
 * @param enrollees The list of CareProgramEnrollee records for which events are to be published.
 */ 
    public static void triggerEvent(List<CareProgramEnrollee> enrollees){
        
        List<Patient_Hub_Tracking_Event__e> trackingEvents = new List<Patient_Hub_Tracking_Event__e>();
        for(CareProgramEnrollee enrollee : enrollees){
            trackingEvents.add(new Patient_Hub_Tracking_Event__e(Enrollee_Id__c = enrollee.Id, Patient_Id__c = enrollee.AccountId));
        }
        
        // Call method to publish events
        List<Database.SaveResult> results = EventBus.publish(trackingEvents);
        
        // Inspect publishing result for each event
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                GenericLogger.debugLog('Successfully published Hub.');
                
            } else {
                for(Database.Error err : sr.getErrors()) {
                    GenericLogger.debugLog('Error returned: ' +
                                           err.getStatusCode() +
                                           ' - ' +
                                           err.getMessage());
                }
            }       
        }
    }
}
