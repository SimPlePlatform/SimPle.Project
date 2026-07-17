@description('The Azure Container Apps managed environment ID created for this single-instance portfolio demo.')
param managedEnvironmentId string

@description('The Azure region. Keep this close to the student account and the chosen Neon region.')
param location string = resourceGroup().location

@description('Name of the public Container App.')
param containerAppName string

@description('Public, immutable Caddy gateway image digest from SimPle.Project.')
param gatewayImage string

@description('Public, immutable frontend image digest from SimpLe.Frontend.')
param frontendImage string

@description('Public, immutable backend image digest from SimPLe.Backend.')
param backendImage string

@secure()
@description('SSL-required Neon PostgreSQL connection string for the application user.')
param databaseConnectionString string

@secure()
@description('Schema-owner Neon PostgreSQL connection string used only by the idempotent migration and seed init jobs.')
param migrationDatabaseConnectionString string

@secure()
param jwtSecretKey string

@secure()
param lobbyCredentialKey string

@secure()
param recaptchaSecretKey string

@secure()
param googleClientId string

@secure()
param emailFrom string

@secure()
param emailSmtpHost string

@secure()
param emailSmtpUsername string

@secure()
param emailSmtpPassword string

@secure()
@description('Backblaze B2 S3-compatible application key ID.')
param storageAccessKey string

@secure()
@description('Backblaze B2 S3-compatible application key secret.')
param storageSecretKey string

@secure()
@description('Public application origin, for example https://your-app.region.azurecontainerapps.io.')
param appOrigin string

@description('B2 bucket name. This is configuration, not a credential.')
param storageBucketName string

@description('B2 S3 endpoint, for example https://s3.us-east-005.backblazeb2.com.')
param storageServiceUrl string

@description('B2 region used by the S3-compatible client.')
param storageRegion string = 'us-east-005'

@description('Public reCAPTCHA site key compiled into the frontend image; recorded here only for deployment evidence.')
param recaptchaSiteKey string

@description('Email sender label.')
param emailFromName string = 'SimPle'

@description('SMTP submission port. Gmail app passwords use 587, never 25.')
param emailSmtpPort int = 587

var secrets = [
  { name: 'database-connection-string', value: databaseConnectionString }
  { name: 'migration-database-connection-string', value: migrationDatabaseConnectionString }
  { name: 'jwt-secret-key', value: jwtSecretKey }
  { name: 'lobby-credential-key', value: lobbyCredentialKey }
  { name: 'recaptcha-secret-key', value: recaptchaSecretKey }
  { name: 'google-client-id', value: googleClientId }
  { name: 'email-from', value: emailFrom }
  { name: 'email-smtp-host', value: emailSmtpHost }
  { name: 'email-smtp-username', value: emailSmtpUsername }
  { name: 'email-smtp-password', value: emailSmtpPassword }
  { name: 'storage-access-key', value: storageAccessKey }
  { name: 'storage-secret-key', value: storageSecretKey }
  { name: 'app-origin', value: appOrigin }
]

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: secrets
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      // Phase 1 safety boundary: Caddy, frontend, workers, and SignalR all share exactly one backend process.
      scale: {
        minReplicas: 0
        maxReplicas: 1
      }
      // These idempotent init jobs run once for each newly created revision, before any public container starts.
      // They make an app revision fail closed rather than serve a schema that its code does not understand.
      initContainers: [
        {
          name: 'migrate'
          image: backendImage
          args: ['--apply-migrations']
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'ConnectionStrings__DefaultConnection', secretRef: 'migration-database-connection-string' }
          ]
        }
        {
          name: 'seed'
          image: backendImage
          args: ['--seed']
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'ConnectionStrings__DefaultConnection', secretRef: 'migration-database-connection-string' }
          ]
        }
      ]
      containers: [
        {
          name: 'gateway'
          image: gatewayImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/live'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
        {
          name: 'frontend'
          image: frontendImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
        {
          name: 'backend'
          image: backendImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
            { name: 'ASPNETCORE_URLS', value: 'http://+:8081' }
            { name: 'ConnectionStrings__DefaultConnection', secretRef: 'database-connection-string' }
            { name: 'Jwt__Issuer', value: 'SimPle' }
            { name: 'Jwt__Audience', value: 'SimPle' }
            { name: 'Jwt__SecretKey', secretRef: 'jwt-secret-key' }
            { name: 'LobbyCredential__Key', secretRef: 'lobby-credential-key' }
            { name: 'LobbyCredential__DefaultRegion', value: 'eu-west' }
            { name: 'Recaptcha__SecretKey', secretRef: 'recaptcha-secret-key' }
            { name: 'Recaptcha__VerificationUrl', value: 'https://www.google.com/recaptcha/api/siteverify' }
            { name: 'Google__ClientId', secretRef: 'google-client-id' }
            { name: 'Email__From', secretRef: 'email-from' }
            { name: 'Email__FromName', value: emailFromName }
            { name: 'Email__SmtpHost', secretRef: 'email-smtp-host' }
            { name: 'Email__SmtpPort', value: string(emailSmtpPort) }
            { name: 'Email__Username', secretRef: 'email-smtp-username' }
            { name: 'Email__Password', secretRef: 'email-smtp-password' }
            { name: 'Email__AppUrl', secretRef: 'app-origin' }
            { name: 'Storage__Provider', value: 'S3Compatible' }
            { name: 'Storage__BucketName', value: storageBucketName }
            { name: 'Storage__Region', value: storageRegion }
            { name: 'Storage__ServiceUrl', value: storageServiceUrl }
            { name: 'Storage__AccessKey', secretRef: 'storage-access-key' }
            { name: 'Storage__SecretKey', secretRef: 'storage-secret-key' }
            { name: 'Storage__ProfilePrefix', value: 'profile-assets' }
            { name: 'Storage__ForcePathStyle', value: 'false' }
            { name: 'Cors__AllowedOrigin', secretRef: 'app-origin' }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/live'
                port: 8081
              }
              initialDelaySeconds: 15
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health/ready'
                port: 8081
              }
              initialDelaySeconds: 20
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 6
            }
          ]
        }
      ]
    }
  }
}

output containerAppFqdn string = app.properties.configuration.ingress.fqdn
output publicOrigin string = 'https://${app.properties.configuration.ingress.fqdn}'
output deployedBackendImage string = backendImage
output deployedFrontendImage string = frontendImage
output gatewayImageDigest string = gatewayImage
output configuredRecaptchaSiteKey string = recaptchaSiteKey
