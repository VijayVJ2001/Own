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
                        //List<String> sourceObjects = getTrackinObjects(event.Patient_Status_Code__c);
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
        // Initialize context object
        HubTrackingContext context = new HubTrackingContext(enrolleeId, patientId);

        // Get CarePlan record type
        context.carePlanRecordTypeId = getCarePlanRecordTypeId();

        // Initialize Hub Tracking record
        initializeHubTracking(context);

        // Query CareProgramEnrollee
        context.enrollee = queryCareProgramEnrollee(enrolleeId);

        // Populate Brand Name
        populateBrandName(context);

        // Populate fields from related objects
        populateFieldsFromSourceObjects(context);

        // Populate consents
        populateConsents(context);

        // Populate case data
        populateCaseData(context);

        // Populate coverage benefits
        populateCoverageBenefits(context);

        // Populate charitable data
        populateCharitableData(context);

        // Set default values if blank
        setDefaultValues(context);

        // Add to hubTrackings and create multiple records
        hubTrackings.add(context.hubTracking);
        createMultipleRecords(enrolleeId, patientId);
    }

    private static Id getCarePlanRecordTypeId() {
        return [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND Name = 'CarePlan' LIMIT 1].Id;
    }

    private static void initializeHubTracking(HubTrackingContext context) {
        context.hubTracking.PHI_Consent__c = 'N';
        context.hubTracking.HIPPA_Consent__c = 'N';
        context.hubTracking.Referral_Source__c = 'HUB';
        context.hubTracking.RX_Recieved__c = 'N';
        context.hubTracking.Primary_Prior_Authorization_Required__c = 'N';
    }

    private static CareProgramEnrollee queryCareProgramEnrollee(String enrolleeId) {
        return [SELECT Id, HCP_Lead__c, HCP_Lead__r.Lead_ID__c, Lead.Lead_ID__c, LeadId, Status, Sub_Status__c, CareProgramId 
                FROM CareProgramEnrollee WHERE Id = :enrolleeId WITH SECURITY_ENFORCED];
    }

    private static void populateBrandName(HubTrackingContext context) {
        List<CareProgramProduct> products = [SELECT Id, Product.Name, CareProgramId 
                                             FROM CareProgramProduct 
                                             WHERE CareProgramId = :context.enrollee.CareProgramId 
                                             WITH SECURITY_ENFORCED LIMIT 1];
        if (!products.isEmpty()) {
            context.hubTracking.Brand_Name__c = products[0].Product.Name;
        }
    }

    private static void populateFieldsFromSourceObjects(HubTrackingContext context) {
        // Prepare mappings and queries in bulk
        Map<String, List<Hub_Tracking_Field_Mapping__mdt>> mappingsByObject = new Map<String, List<Hub_Tracking_Field_Mapping__mdt>>();
        Map<String, List<SObject>> recordsByObject = new Map<String, List<SObject>>();
    
        // Query all mappings for the source objects
        for (String sourceObjectName : sourceObjectNames) {
            mappingsByObject.put(sourceObjectName, 
                [SELECT Id, SourceField__c, Target_Object__r.QualifiedAPIName, Target_Field__r.QualifiedAPIName 
                 FROM Hub_Tracking_Field_Mapping__mdt 
                 WHERE Source_Object__r.QualifiedAPIName = :sourceObjectName WITH SECURITY_ENFORCED]);
        }
    
        // Query all source records for the objects
        for (String sourceObjectName : sourceObjectNames) {
            List<Hub_Tracking_Field_Mapping__mdt> mappings = mappingsByObject.get(sourceObjectName);
            if (!mappings.isEmpty()) {
                List<SObject> sourceRecords = querySourceObject(context.enrolleeId, context.patientId, sourceObjectName, mappings);
                recordsByObject.put(sourceObjectName, sourceRecords);
            }
        }
    
        // Process the data
        for (String sourceObjectName : recordsByObject.keySet()) {
            List<SObject> sourceRecords = recordsByObject.get(sourceObjectName);
            List<Hub_Tracking_Field_Mapping__mdt> mappings = mappingsByObject.get(sourceObjectName);
    
            for (SObject sourceObject : sourceRecords) {
                for (Hub_Tracking_Field_Mapping__mdt mapping : mappings) {
                    mapSourceObjectFields(context.hubTracking, sourceObject, mapping, sourceObjectName);
                }
            }
        }
    }

    private static void mapSourceObjectFields(T_Hub_Tracking__c hubTracking, SObject sourceObject, Hub_Tracking_Field_Mapping__mdt mapping, String sourceObjectName) {
        String sourceFieldValue = getFieldValue(sourceObject, mapping.SourceField__c);

        if (sourceObjectName == 'MemberPlan') {
            handleMemberPlanMappings(hubTracking, sourceObject, mapping, sourceFieldValue);
        } else if (sourceObjectName == 'J_Charitable__c') {
            handleCharitableMappings(hubTracking, sourceObject, mapping, sourceFieldValue);
        } else {
            hubTracking.put(mapping.Target_Field__r.QualifiedAPIName, sourceFieldValue);
        }
    }

    private static void handleMemberPlanMappings(T_Hub_Tracking__c hubTracking, SObject sourceObject, Hub_Tracking_Field_Mapping__mdt mapping, String sourceFieldValue) {
        if (sourceObject.get('J_Role__c') == 'Primary' && mapping.Target_Field__r.QualifiedAPIName.containsIgnoreCase('Primary')) {
            hubTracking.put(mapping.Target_Field__r.QualifiedAPIName, sourceFieldValue);
        } else if (sourceObject.get('J_Role__c') == 'Secondary' && mapping.Target_Field__r.QualifiedAPIName.containsIgnoreCase('Secondary')) {
            hubTracking.put(mapping.Target_Field__r.QualifiedAPIName, sourceFieldValue);
        }
    }

    private static void handleCharitableMappings(T_Hub_Tracking__c hubTracking, SObject sourceObject, Hub_Tracking_Field_Mapping__mdt mapping, String sourceFieldValue) {
        if (sourceObject.get('J_CharitableProgramType__c') == 'TPAP' && mapping.Target_Field__r.QualifiedAPIName.containsIgnoreCase('TPAP')) {
            hubTracking.put(mapping.Target_Field__r.QualifiedAPIName, sourceFieldValue);
        } else if (sourceObject.get('J_CharitableProgramType__c') != 'TPAP' && !mapping.Target_Field__r.QualifiedAPIName.containsIgnoreCase('TPAP')) {
            hubTracking.put(mapping.Target_Field__r.QualifiedAPIName, sourceFieldValue);
        }
    }

    private static void populateConsents(HubTrackingContext context) {
        List<AuthorizationFormConsent> consents = [SELECT Id, J_ConsentExpirationDate__c, J_ConsentStatus__c, Signatured_Date_PHI__c 
                                                   FROM AuthorizationFormConsent 
                                                   WHERE Care_Program_Enrollee__c = :context.enrolleeId AND J_TypeOfConsent__c = 'Patient Authorization' WITH SECURITY_ENFORCED];
        for (AuthorizationFormConsent consent : consents) {
            if (consent.J_ConsentStatus__c == 'Active') {
                context.hubTracking.PHI_Consent__c = 'Y';
                context.hubTracking.HIPPA_Consent__c = 'Y';
                context.hubTracking.HIPPA_Consent_Date__c = String.valueOf(consent.J_ConsentExpirationDate__c)?.replaceAll('-', '');
            }
        }
    }

    private static void populateCaseData(HubTrackingContext context) {
        List<Case> cases = [SELECT Id, Disease__c 
                            FROM Case 
                            WHERE Care_Program_Enrollee__c = :context.enrolleeId AND RecordTypeId = :context.carePlanRecordTypeId WITH SECURITY_ENFORCED];
        for (Case tp : cases) {
            context.hubTracking.Indication__c = (tp.Disease__c == 'Fibrodysplasia Ossificans Progressiva (FOP)') ? 'FOP' : tp.Disease__c;
        }
    }

    private static void populateCoverageBenefits(HubTrackingContext context) {
        List<CoverageBenefit> benefits = [SELECT Id, J_PriorAuthorizationRequired__c, J_BenefitType__c, MemberPlan.Status, MemberPlan.J_Role__c, J_CoPay__c, J_OOPMax__c 
                                          FROM CoverageBenefit 
                                          WHERE Care_Program_Enrollee__c = :context.enrolleeId AND J_CoverageBenefitStatus__c = 'Active' WITH SECURITY_ENFORCED LIMIT 3];
        for (CoverageBenefit benefit : benefits) {
            if (benefit.MemberPlan.Status == 'Active' && benefit.MemberPlan.J_Role__c == 'Primary') {
                if (benefit.J_PriorAuthorizationRequired__c == 'Yes') {
                    context.hubTracking.Primary_Prior_Authorization_Required__c = 'Y';
                }
                context.hubTracking.PRIMARY_BENEFIT_TYPE__c = benefit.J_BenefitType__c;
                context.hubTracking.PRIMARY_COPAY_AMOUNT__c = benefit.J_CoPay__c;
                context.hubTracking.FINAL_PATIENT_OUT_OF_POCKET_COST__c = benefit.J_OOPMax__c;
            }
        }
    }

    private static void populateCharitableData(HubTrackingContext context) {
        List<J_Charitable__c> charitables = [SELECT Id, J_CharitableProgramType__c, J_Enrollment_End_Date__c 
                                             FROM J_Charitable__c 
                                             WHERE Care_Program_Enrollee__c = :context.enrolleeId AND J_CharitableStatus__c = 'Active' WITH SECURITY_ENFORCED LIMIT 1];
        for (J_Charitable__c charitable : charitables) {
            if (charitable.J_CharitableProgramType__c == 'TPAP') {
                context.hubTracking.TPAP_Expiration_Date__c = String.valueOf(charitable.J_Enrollment_End_Date__c)?.replaceAll('-', '');
            }
        }
    }

    private static void setDefaultValues(HubTrackingContext context) {
        if (String.isBlank(context.hubTracking.Patient_State__c)) {
            context.hubTracking.Patient_State__c = 'NA';
        }
        if (String.isBlank(context.hubTracking.Referral_Source__c)) {
            context.hubTracking.Referral_Source__c = 'HUB';
        }
    }

// Context Helper Class
public class HubTrackingContext {
    public String enrolleeId;
    public String patientId;
    public Id carePlanRecordTypeId;
    public CareProgramEnrollee enrollee;
    public T_Hub_Tracking__c hubTracking;

    public HubTrackingContext(String enrolleeId, String patientId) {
        this.enrolleeId = enrolleeId;
        this.patientId = patientId;
        this.hubTracking = new T_Hub_Tracking__c();
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