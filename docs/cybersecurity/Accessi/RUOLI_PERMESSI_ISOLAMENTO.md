# Ruoli, permessi e isolamento tra clienti e organizzazioni

Aggiornamento: 23 novembre 2026.

## Siti e associazioni di accesso

Il **sito** è l'unità di organizzazione degli accessi: raggruppa uno o più server, identificati da un numero seriale univoco, e gli utenti autorizzati a utilizzarli. La gestione dei siti consente di associare server, utenti e ruoli in funzione delle esigenze del cliente.

Le associazioni configurate alimentano le informazioni sui siti e sui server recuperate da uSee e uSS tramite il servizio SSO. Dopo l'autenticazione, uSee presenta all'utente i siti ai quali è autorizzato ad accedere.

## Ruoli e permessi

Il modello distingue la **gestione amministrativa del sito** dai **permessi operativi nell'applicazione**.

| Ruolo o funzione | Ambito |
|---|---|
| Site Manager | Crea e modifica i siti, associa i server, aggiunge e autorizza gli utenti, assegna ruoli e crea ruoli personalizzati. Può nominare ulteriori Site Manager. |
| Executive | Profilo operativo predefinito con tutti gli attributi di autorizzazione attivi. |
| PowerUser | Profilo operativo predefinito con gli attributi attivi, ad eccezione della configurazione del server. |
| User | Profilo operativo predefinito, con i permessi associati al ruolo. |
| Ruoli personalizzati | Profili definiti per il sito mediante la selezione di singoli attributi di autorizzazione, anche copiando quelli di un ruolo esistente. |

La qualifica di Site Manager è assegnata separatamente dal ruolo operativo. Gli attributi rappresentano singole azioni o autorizzazioni, ad esempio la consultazione degli eventi, l'utilizzo di chat e videochiamate e specifiche operazioni di configurazione delle telecamere.

L'inserimento di un utente comprende l'account identificato tramite e-mail, il ruolo operativo, l'eventuale qualifica di Site Manager e le credenziali di accesso al server. L'utente riceve un invito e completa la registrazione se non dispone già di un account.

## Autenticazione e accesso ai server

uSee autentica l'utente presso il servizio SSO centrale e utilizza credenziali separate per collegarsi ai singoli server Arteco. La gestione del sito associa all'utente il nome utente e la password dell'account configurato sul server.

Il servizio SSO restituisce i siti, i server e le informazioni applicative associati all'utente autenticato. L'identità centrale e gli account dei server costituiscono quindi due livelli distinti del modello di accesso.

## Separazione logica degli accessi

La separazione degli accessi tra clienti e organizzazioni si articola attraverso i **siti**, le **associazioni esplicite degli utenti** e i **ruoli assegnati nel sito**. La visibilità dei siti e dei prodotti collegati è riservata agli utenti autorizzati dal Site Manager.

Il modello permette di organizzare gruppi di server e utenti con ambiti di accesso distinti. Un utente può accedere a più siti quando dispone delle relative autorizzazioni; i permessi operativi sono determinati dal ruolo assegnato nel relativo sito.
