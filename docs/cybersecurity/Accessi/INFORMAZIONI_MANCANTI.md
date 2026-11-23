# Promemoria interno - Ruoli, permessi e isolamento

Aggiornamento: 23 novembre 2026.

## Base documentale e perimetro

- Manuale consultato: `/Users/lucavolta/Documents/uSS - DOCS/Bos/SITE MANAGEMENT_User Manual_ITA.pdf`, in particolare pagine PDF 3, 8-12 e 13. Le descrizioni di Executive e PowerUser sono leggibili nell'interfaccia riportata a pagina PDF 12.
- Il manuale descrive un modello di associazioni per sito. Non dimostra isolamento fisico, database separati per cliente, un'entità organizzazione/tenant distinta o l'effettiva applicazione server-side di tutti i controlli.
- La gestione amministrativa sul portale alimenta le associazioni recuperate dall'SSO; questo non modifica il perimetro operativo già concordato: le Lambda accedono direttamente al DB, indipendentemente dalla disponibilità del portale WordPress.

## Verifiche prioritarie

- [ ] Verificare l'applicazione server-side delle autorizzazioni su ogni API uSee/uSS, includendo tentativi di accesso a siti, seriali e risorse di altri utenti/clienti mediante modifica degli identificativi.
- [ ] Chiarire il rapporto cliente/organizzazione/sito: proprietà dei siti, eventuali tenant, siti condivisi, utenti multi-sito e poteri degli amministratori del fornitore.
- [ ] Verificare i filtri per sito/utente su dati applicativi, eventi, ricerche, export, WebSocket, sottoscrizioni Redis e accesso a video e registrazioni.
- [ ] Acquisire la matrice completa e attuale degli attributi dei ruoli Executive, PowerUser e User e verificare l'effettiva implementazione. Il manuale non specifica i permessi del ruolo User; alcuni attributi di auditing mostrati sono marcati DRAFT.
- [ ] Chiarire la relazione e l'eventuale precedenza tra ruolo del sito e permessi dell'account locale del server, incluse credenziali eventualmente condivise tra utenti.
- [ ] Verificare conservazione, cifratura, distribuzione e rotazione delle credenziali dei server associate agli utenti; evitare di assimilare tali credenziali agli hash delle password SSO.
- [ ] Verificare propagazione e tempi di efficacia di revoche, rimozione da un sito, cambi di ruolo e disabilitazione account su sessioni e token già emessi, sia in uSee sia in uSS.
- [ ] Verificare tracciamento delle modifiche a utenti, ruoli, server e siti, inclusi autore, data, conservazione e consultazione dei log.
- [ ] Chiarire trasferimento e revoca della qualifica di Site Manager: il manuale indica che il Site Manager non può rinunciare al ruolo ma può nominarne altri.
