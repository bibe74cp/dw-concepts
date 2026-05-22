# Architettura Data Warehouse - Concetti Fondamentali

## Indice
- [Introduzione](#introduzione)
- [Cos'è un Data Warehouse?](#cosè-un-data-warehouse)
- [L'Architettura a Due Livelli](#larchitettura-a-due-livelli)
- [Concetti Fondamentali Spiegati](#concetti-fondamentali-spiegati)
- [Il Viaggio dei Dati](#il-viaggio-dei-dati)
- [Principali Vantaggi](#principali-vantaggi)
- [Analogia del Mondo Reale](#analogia-del-mondo-reale)
- [Letture Consigliate](#letture-consigliate)

## Introduzione

Questo documento spiega l'architettura e i concetti alla base del nostro sistema di data warehouse in un linguaggio chiaro e non tecnico. Che tu sia un analista di business, un manager o uno stakeholder, questa guida ti aiuterà a comprendere come organizziamo, archiviamo e prepariamo i dati per la business intelligence e il reporting.

Il nostro approccio si basa sulla **metodologia Kimball**, uno standard industriale ampiamente riconosciuto per la costruzione di data warehouse che si è dimostrato efficace in migliaia di organizzazioni in tutto il mondo fin dagli anni '90.

## Cos'è un Data Warehouse?

### Definizione

Un **data warehouse** è un repository centralizzato dove i dati provenienti da vari sistemi aziendali (come ERP, CRM o sistemi di produzione) vengono raccolti, organizzati e preparati per l'analisi e il reporting.

Pensalo come una biblioteca per i tuoi dati aziendali:
- Proprio come una biblioteca raccoglie libri da vari editori e li organizza per facilitarne la scoperta
- Un data warehouse raccoglie dati da vari sistemi aziendali e li organizza per facilitarne l'analisi

**Principali differenze rispetto ai sistemi operazionali:**

| Sistema Operazionale (ERP, CRM) | Data Warehouse |
|--------------------------------|----------------|
| Progettato per transazioni quotidiane | Progettato per analisi e reporting |
| Ottimizzato per velocità di aggiornamento | Ottimizzato per velocità di interrogazione |
| Memorizza dati attuali | Memorizza dati storici nel tempo |
| Utilizzato da dipendenti che svolgono il loro lavoro | Utilizzato da analisti e decision maker |
| Dati organizzati per efficienza | Dati organizzati per comprensione |

### Perché Abbiamo Bisogno di un Data Warehouse?

**Problema**: I dati aziendali risiedono in molti sistemi diversi:
- Dati clienti nel tuo CRM (Salesforce)
- Dati ordini nel tuo sistema ERP
- Dati di produzione nel tuo sistema manifatturiero
- Ogni sistema ha la propria struttura e terminologia

**Soluzione**: Un data warehouse:
- ✅ Riunisce tutti i dati in un unico luogo
- ✅ Li organizza in modo coerente e comprensibile
- ✅ Conserva le modifiche storiche nel tempo
- ✅ Rende veloce rispondere alle domande di business
- ✅ Non rallenta i tuoi sistemi operazionali

**Letture consigliate**: [Data Warehouse - Wikipedia](https://it.wikipedia.org/wiki/Data_warehouse)

## L'Architettura a Due Livelli

Il nostro data warehouse utilizza un'**architettura a due livelli**, ciascuno dei quali serve uno scopo specifico nel viaggio dei dati dai sistemi sorgente ai report aziendali.

```
Sistemi Sorgente → Landing Zone → Data Warehouse → Report & Analytics
(ERP, CRM, MES)   (Livello 1)     (Livello 2)      (Power BI, Excel)
```

### Livello 1: La Landing Zone

**Scopo**: Un'area di staging sicura dove i dati grezzi arrivano per la prima volta dai sistemi sorgente.

**Analogia**: Pensa a una banchina di carico in un magazzino:
- I pacchi (dati) arrivano da diversi fornitori (sistemi sorgente)
- Ognuno viene controllato, etichettato e organizzato
- Niente viene buttato via; tutto viene tracciato
- I problemi di qualità vengono identificati prima di passare allo stoccaggio

**Cosa succede qui:**
- I dati vengono copiati dai sistemi sorgente (ERP, Salesforce, ecc.)
- Ogni sistema sorgente ottiene il proprio spazio organizzato
- Le modifiche vengono tracciate (cosa è nuovo, cosa è cambiato, cosa è stato eliminato)
- La qualità dei dati viene verificata
- Viene mantenuta una traccia di audit completa

**Principio chiave**: La Landing Zone è una **copia fedele** dei dati sorgente con trasformazioni minime. Tracciamo da dove provengono i dati e quando sono arrivati.

### Livello 2: Il Data Warehouse

**Scopo**: Archiviazione organizzata ottimizzata per analisi e reporting aziendali.

**Analogia**: Pensa a una biblioteca aziendale ben organizzata:
- I libri (dati) sono catalogati per argomento (dimensioni come Cliente, Prodotto, Data)
- Gli eventi (come le transazioni di vendita) fanno riferimento a questi argomenti
- Le informazioni correlate sono mantenute insieme
- Facile trovare ciò di cui hai bisogno per qualsiasi domanda

**Cosa succede qui:**
- I dati da più sorgenti vengono combinati e unificati
- Vengono applicati nomi e strutture business-friendly
- Organizzati in **dimensioni** (chi, cosa, quando, dove) e **fatti** (misurazioni, eventi)
- Ottimizzati per rispondere rapidamente alle domande di business
- Create viste curate per dipartimenti o applicazioni specifici

**Principio chiave**: Il Data Warehouse è organizzato attorno ai **processi di business** (come Vendite, Produzione, Inventario) piuttosto che ai sistemi tecnici.

## Concetti Fondamentali Spiegati

### Modellazione Dimensionale (Metodologia Kimball)

La **modellazione dimensionale** è una tecnica di progettazione che organizza i dati in due tipi di tabelle:

1. **Tabelle Dimensionali**: Descrivono il contesto aziendale (il "CHI, COSA, QUANDO, DOVE, PERCHÉ")
2. **Tabelle dei Fatti**: Registrano misurazioni ed eventi (il "QUANTO, QUANTI")

Questo approccio è stato pionieristico di **Ralph Kimball**, un architetto di data warehouse leader, ed è documentato nel suo influente libro "The Data Warehouse Toolkit".

**Perché è importante:**
- Rende i dati intuitivi da comprendere per gli utenti aziendali
- Abilita query e report veloci
- Flessibile per rispondere a domande impreviste
- Approccio collaudato dall'industria utilizzato in tutto il mondo

**Letture consigliate**: 
- [Modellazione Dimensionale - Wikipedia](https://en.wikipedia.org/wiki/Dimensional_modeling)
- [Star Schema - Wikipedia](https://en.wikipedia.org/wiki/Star_schema)

### Dimensioni: Il Contesto del Tuo Business

Le **dimensioni** sono i sostantivi del tuo business - le persone, i prodotti, le località e i periodi temporali che forniscono contesto alle tue metriche.

**Esempi di dimensioni:**
- **Cliente**: Chi ha comprato qualcosa? (nome, categoria, regione, segmento)
- **Prodotto**: Cosa è stato venduto? (nome, categoria, marca, dimensione)
- **Data**: Quando è successo? (giorno, settimana, mese, trimestre, anno)
- **Dipendente**: Chi è stato coinvolto? (nome, dipartimento, ruolo, manager)
- **Località**: Dove è avvenuto? (negozio, magazzino, regione, paese)

**Pensa alle dimensioni come alle domande che poni:**
- "Mostrami le vendite per **cliente**"
- "Mostrami la produzione per **prodotto** e **data**"
- "Mostrami gli ordini per **regione** e **dipendente**"

**Caratteristiche chiave:**
- Relativamente piccole (centinaia a milioni di righe)
- Attributi descrittivi (testo, categorie, gerarchie)
- Cambiano lentamente nel tempo
- Utilizzate per filtrare, raggruppare ed etichettare i tuoi report

### Fatti: Le Misurazioni del Tuo Business

I **fatti** sono i verbi e le misurazioni del tuo business - le transazioni, gli eventi e le metriche che vuoi analizzare.

**Esempi di fatti:**
- **Transazione di Vendita**: Un cliente ha comprato un prodotto per un certo importo
- **Ordine di Produzione**: Una quantità di prodotti è stata prodotta
- **Snapshot dell'Inventario**: Il livello delle scorte in un punto nel tempo
- **Visita al Sito Web**: Un cliente ha visualizzato una pagina per una durata

**Pensa ai fatti come alle risposte che cerchi:**
- "**Quanto** abbiamo venduto?"
- "**Quante** unità sono state prodotte?"
- "**Qual era** il valore dell'inventario?"

**Caratteristiche chiave:**
- Molto grandi (milioni a miliardi di righe)
- Misurazioni numeriche (importi, quantità, durate)
- Ogni riga rappresenta un evento di business specifico
- Fa riferimento a dimensioni per fornire contesto

### Lo Star Schema: Come Si Collega Tutto

Lo **star schema** è la disposizione delle dimensioni attorno ai fatti, che assomiglia a una stella:

```
        Cliente
           |
           |
Prodotto -- FATTO VENDITE -- Data
           |
           |
        Dipendente
```

**Come leggerlo:**
- Il centro (FATTO VENDITE) contiene misurazioni: quantità venduta, ricavi, profitto
- Ogni punto della stella (dimensioni) fornisce contesto: chi, cosa, quando, dove
- Per rispondere a "Quali erano le vendite per prodotto e cliente?", basta collegare i punti

**Vantaggi per gli utenti non tecnici:**
- Struttura intuitiva che corrisponde a come pensi al business
- Facile da comprendere senza competenze tecniche
- Veloce da interrogare e su cui fare report
- Flessibile per analisi ad-hoc

**Letture consigliate**: [Star Schema - Wikipedia](https://en.wikipedia.org/wiki/Star_schema)

### Tracciamento delle Modifiche: Sapere Cosa è Cambiato e Quando

**La sfida aziendale:**
- Gli indirizzi dei clienti cambiano
- I prezzi dei prodotti cambiano
- I ruoli dei dipendenti cambiano
- Come gestiamo questi cambiamenti nei nostri dati storici?

**Il nostro approccio - Rilevamento delle Modifiche Basato su Hash:**

Invece di confrontare ogni colonna per rilevare le modifiche, utilizziamo una tecnica chiamata **hashing**:
- Pensala come un'impronta digitale per ogni record
- Se qualsiasi dato cambia, l'impronta digitale cambia
- Possiamo individuare rapidamente cosa è diverso senza esaminare ogni dettaglio

**Vantaggi:**
- Rilevamento veloce delle modifiche (millisecondi vs. minuti)
- Accuratezza completa (ogni modifica viene catturata)
- Funziona con qualsiasi sistema sorgente
- Uso efficiente delle risorse di calcolo

**Letture consigliate**: [Funzione Hash - Wikipedia](https://it.wikipedia.org/wiki/Funzione_di_hash)

### Eliminazioni Soft: Non Perdere Mai la Storia

**La sfida aziendale:**
Quando un cliente viene rimosso dal tuo CRM o un prodotto viene dismesso, dovremmo eliminarlo dal data warehouse?

**Il nostro approccio - Eliminazione Soft:**

Invece di rimuovere fisicamente i record, li **contrassegnamo come eliminati** mantenendo i dati:
- Il record rimane nel database
- Contrassegnato come "eliminato" così non appare nei report attuali
- Ancora disponibile per analisi storiche

**Esempio del mondo reale:**
- Un cliente chiude il suo account a gennaio 2025
- Lo contrassegniamo come eliminato ma manteniamo i suoi dati
- I report per il 2024 mostrano ancora le sue vendite (perché era un cliente allora)
- I report per il 2026 lo escludono (perché non è più un cliente)
- Se ritorna nel 2027, possiamo riattivarlo con l'intera cronologia intatta

**Vantaggi:**
- Traccia di audit completa (conformità normativa)
- I report storici rimangono accurati
- Possibilità di recuperare da eliminazioni accidentali
- Possibilità di analizzare i pattern (perché i clienti se ne vanno?)

### Chiavi Surrogate: Identificatori Stabili

**La sfida aziendale:**
- Sistemi diversi utilizzano ID cliente diversi
- Gli ID cliente potrebbero essere riutilizzati o modificati
- Le chiavi composite (come Azienda + Cliente) sono ingombranti

**Il nostro approccio - Chiavi Surrogate:**

Assegniamo i nostri identificatori semplici e stabili:
- Ogni cliente ottiene un numero unico (1, 2, 3, ...) che non cambia mai
- Questo numero è indipendente dal sistema sorgente
- Rende semplice e veloce collegare i dati

**Analogia**: Come il numero di una tessera bibliotecaria:
- Il numero della tua tessera bibliotecaria (chiave surrogata) non cambia mai
- Anche se cambi indirizzo o numero di telefono (chiavi naturali)
- La biblioteca può sempre trovare i tuoi record usando il numero della tessera

**Vantaggi:**
- Ricerche semplici e veloci
- Indipendente dalle modifiche del sistema sorgente
- Abilita l'integrazione tra più sistemi
- Supporta il tracciamento storico

**Letture consigliate**: [Chiave Surrogata - Wikipedia](https://it.wikipedia.org/wiki/Chiave_surrogata)

### Membri Speciali: Gestione dei Dati Mancanti

**La sfida aziendale:**
Cosa succede quando un fatto fa riferimento a una dimensione che non esiste?
- Un ordine senza cliente assegnato
- Una vendita dove non conosciamo il prodotto
- Una transazione da un dipendente sconosciuto

**Il nostro approccio - Membri Speciali:**

Creiamo due record speciali in ogni dimensione:

1. **Membro Vuoto** (Non Applicabile):
   - Utilizzato quando la dimensione non si applica
   - Esempio: Un ordine piazzato dal sistema non ha venditore

2. **Membro Sconosciuto** (Riferimento Mancante):
   - Utilizzato quando ci aspettavamo un valore ma è mancante o non valido
   - Esempio: Un ordine fa riferimento al cliente #999 ma quel cliente non esiste

**Vantaggi:**
- Tutte le transazioni vengono caricate con successo (nessuna perdita di dati)
- Possibilità di identificare e correggere problemi di qualità dei dati
- I report funzionano senza errori
- Mantiene l'integrità dei dati

**Esempio del mondo reale:**
Nel tuo report delle vendite, potresti vedere:
- La maggior parte delle vendite assegnate a clienti reali
- Alcune a "(Sconosciuto)" - che indicano un problema di qualità dei dati da investigare
- Alcune a "(Non Applicabile)" - ordini generati dal sistema senza cliente

### Idempotenza: Sicuro da Eseguire Ripetutamente

**La sfida aziendale:**
Cosa succede se un caricamento dati fallisce a metà? O viene eseguito due volte per errore?

**Il nostro approccio - Caricamento Idempotente:**

Lo stesso caricamento dati può essere eseguito più volte e produce sempre lo stesso risultato:
- Eseguire una volta = stesso risultato di eseguire dieci volte
- I caricamenti falliti possono essere ritentati in sicurezza
- Nessun record duplicato creato
- Nessuna corruzione dei dati

**Analogia**: Come un interruttore della luce:
- Accendilo "on" una volta - la luce si accende
- Accendilo "on" di nuovo - la luce rimane accesa (non si rompe)
- Stessa azione, stesso risultato

**Vantaggi:**
- Sicuro ritentare caricamenti falliti
- Possibilità di programmare caricamenti sovrapposti
- Riduce la complessità operativa
- Aumenta l'affidabilità

**Letture consigliate**: [Idempotenza - Wikipedia](https://it.wikipedia.org/wiki/Idempotenza)

### Tracciamento Temporale: La Linea Temporale dei Tuoi Dati

**Il concetto aziendale:**
Comprendere non solo **quali** dati hai, ma **quando** sono arrivati e cambiati.

**Cosa tracciamo:**
- **Data di Inserimento**: Quando questo record è apparso per la prima volta nel nostro data warehouse?
- **Data di Aggiornamento**: Quando questo record è stato modificato l'ultima volta?
- **Data di Eliminazione**: Quando questo record è stato contrassegnato come eliminato?

**Valore aziendale:**
- **Freschezza dei Dati**: Quanto sono attuali le nostre informazioni?
- **Analisi delle Modifiche**: Quanto spesso cambiano i dettagli dei clienti?
- **Traccia di Audit**: Chi ha modificato cosa e quando?
- **Monitoraggio SLA**: Stiamo rispettando i nostri impegni di consegna dei dati?
- **Analisi delle Tendenze**: Come è evoluto questo cliente nel tempo?

**Esempio del mondo reale:**
- Record cliente inserito il 1 gennaio 2024 (prima apparizione)
- Ultimo aggiornamento il 15 aprile 2025 (indirizzo modificato)
- Nessuna modifica nell'ultimo anno (cliente stabile)
- Questo ti dice che il cliente è consolidato e stabile

## Il Viaggio dei Dati

### Passo dopo Passo: Come Fluiscono i Dati nel Sistema

#### Passo 1: Estrazione dai Sistemi Sorgente

**Cosa succede:**
- Ogni giorno (o ora), ci colleghiamo ai tuoi sistemi operazionali
- Estraiamo dati nuovi e modificati
- Nessun impatto sulle prestazioni del sistema (leggiamo, non scriviamo mai)

**Esempio:**
- Collegamento al database ERP
- Lettura di tutti i clienti modificati nelle ultime 24 ore
- Lettura di tutti i nuovi ordini creati oggi

#### Passo 2: Arrivo nella Landing Zone

**Cosa succede:**
- I dati arrivano nella Landing Zone (Livello 1)
- Ogni sistema sorgente ha la sua area organizzata
- Le modifiche vengono rilevate automaticamente usando impronte digitali hash
- I record vengono inseriti, aggiornati o contrassegnati come eliminati

**Esempio:**
- 1.250 clienti controllati
- 47 nuovi clienti inseriti
- 23 clienti esistenti aggiornati (modifiche rilevate)
- 5 clienti contrassegnati come eliminati (non più nella sorgente)

**Risultato**: Una copia esatta e tracciata dei dati sorgente

#### Passo 3: Trasformazione in Dimensioni e Fatti

**Cosa succede:**
- I dati si spostano dalla Landing Zone al Data Warehouse (Livello 2)
- Combinati con dati da altre sorgenti
- Organizzati in dimensioni (contesto) e fatti (misurazioni)
- Applicati nomi business-friendly
- Applicate regole di qualità

**Esempio:**
- Dati cliente da ERP + Salesforce → **Dim.Cliente**
- Ordini da ERP → **Fatto.Vendite**
- Dati produzione da MES → **Fatto.Produzione**

**Risultato**: Modello dati unificato e orientato al business

#### Passo 4: Accesso Tramite Viste Applicative

**Cosa succede:**
- Viste specifiche create per ogni consumatore
- Sicurezza applicata (ogni applicazione vede solo ciò di cui ha bisogno)
- Logica complessa nascosta dietro interfacce semplici
- Ottimizzato per le prestazioni

**Esempio:**
- ERP vede vista ordini di produzione
- Power BI vede vista analisi vendite
- Finance vede vista reporting ricavi

**Risultato**: Dati giusti alle persone giuste

#### Passo 5: Reporting e Analisi

**Cosa succede:**
- Gli utenti aziendali collegano i loro strumenti (Power BI, Excel, Tableau)
- Pongono domande di business
- Ottengono risposte veloci e accurate
- Creano dashboard e report

**Esempi di Domande:**
- "Quali erano le vendite per regione l'ultimo trimestre?"
- "Quali prodotti sono i più redditizi?"
- "Come si confronta quest'anno con l'anno scorso?"
- "Quali clienti rischiano di andarsene?"

**Risultato**: Decisioni aziendali guidate dai dati

### Frequenza di Sincronizzazione

**Quanto spesso si aggiornano i dati?**

La frequenza dipende dalle esigenze aziendali:

| Tipo di Dati | Frequenza Tipica | Motivo Aziendale |
|--------------|------------------|------------------|
| Dati Transazionali (Vendite, Ordini) | Oraria o Giornaliera | Necessità di visibilità operativa corrente |
| Dati Anagrafici (Clienti, Prodotti) | Giornaliera | Cambia meno frequentemente |
| Dati di Produzione | Ogni 15-60 minuti | Monitoraggio produzione in tempo reale |
| Dati Finanziari | Giornaliera o Settimanale | Processi di chiusura di fine mese |
| Dati Esterni (Prezzi di mercato) | Secondo disponibilità | Dipende dal fornitore dati |

**Compromessi:**
- Più frequente = più attuale, ma più elaborazione
- Meno frequente = più semplice, ma meno tempestivo
- Ottimizziamo in base alle tue specifiche esigenze aziendali

## Principali Vantaggi

### Per gli Utenti Aziendali

**1. Unica Fonte di Verità**
- Un unico luogo per trovare tutti i dati aziendali
- Definizioni coerenti tra i dipartimenti
- Tutti lavorano con gli stessi numeri

**2. Prospettiva Storica**
- Vedere come le cose sono cambiate nel tempo
- Confrontare periodi (quest'anno vs. anno scorso)
- Identificare tendenze e pattern

**3. Risposte Veloci**
- I report vengono eseguiti in secondi, non ore
- Nessuna attesa per IT per estrarre i dati
- Capacità di analisi self-service

**4. Vista Integrata**
- Vedere i dati cliente sia da ERP che da CRM
- Collegare vendite a produzione a inventario
- Quadro completo delle operazioni aziendali

**5. Qualità dei Dati**
- Problemi identificati e segnalati
- Traccia di audit completa
- Dati validati e verificati

### Per i Team IT e Dati

**1. Scalabilità**
- Gestisce volumi di dati in crescita
- Supporta più sistemi sorgente
- Aggiunge nuove sorgenti dati facilmente

**2. Manutenibilità**
- Pattern chiari e documentati
- Approccio coerente in tutto
- Più facile formare nuovi membri del team

**3. Prestazioni**
- Ottimizzato per query analitiche
- Non rallenta i sistemi operazionali
- Uso efficiente delle risorse di calcolo

**4. Affidabilità**
- Sicuro ritentare caricamenti falliti
- Tracciamento completo degli errori
- Controlli automatici di qualità dei dati

**5. Sicurezza**
- Controllo accessi basato su ruoli
- Isolamento a livello applicazione
- Logging di audit completo

### Per l'Organizzazione

**1. Decisioni Migliori**
- Accesso a informazioni accurate e tempestive
- Capacità di analizzare tendenze e pattern
- Decisioni basate sull'evidenza

**2. Conformità Normativa**
- Traccia di audit completa
- Tracciamento della provenienza dei dati
- Conservazione dati storici

**3. Efficienza Operativa**
- Ridotto sforzo di reporting manuale
- Accesso più rapido alle informazioni
- Controlli automatici di qualità dei dati

**4. Vantaggio Competitivo**
- Insights sul comportamento dei clienti
- Analisi delle tendenze di mercato
- Opportunità di ottimizzazione operativa

**5. Ritorno sull'Investimento**
- Ridotti costi di reporting
- Tempo più rapido per ottenere insights
- Migliori risultati aziendali

## Analogia del Mondo Reale

### Il Data Warehouse come Sistema Bibliotecario Moderno

Immagina il tuo data warehouse come un **moderno sistema bibliotecario cittadino**:

#### Sistemi Sorgente = Editori
- Diversi editori (ERP, CRM, MES) producono libri (dati)
- Ognuno ha il proprio formato e stile
- Nuove edizioni vengono pubblicate regolarmente

#### Landing Zone = Banchina di Ricezione
- I libri arrivano da vari editori
- Ognuno viene catalogato e controllato per qualità
- Danni o pagine mancanti vengono annotati
- Registro di ricezione completo mantenuto
- I libri non vengono modificati, solo organizzati

#### Data Warehouse = Scaffali della Biblioteca
- I libri sono organizzati per argomento (dimensioni)
- I libri correlati sono raggruppati insieme
- Il catalogo (chiavi surrogate) fornisce ricerca facile
- Le guide per argomento (fatti) ti aiutano a trovare ciò di cui hai bisogno
- Sezioni diverse per scopi diversi (schemi)

#### Dimensioni = Sezioni del Catalogo
- **Sezione Autori** (come dimensione Cliente): Chi ha scritto cosa?
- **Sezione Argomenti** (come dimensione Prodotto): Quali argomenti sono coperti?
- **Sezione Periodi Temporali** (come dimensione Data): Quando è stato pubblicato?

#### Fatti = Registri di Circolazione
- **Record di Prestito** (come fatto Vendite): Chi ha preso in prestito quale libro quando?
- **Conteggio Riferimenti** (come fatto Visualizzazioni Pagina): Quante volte è stato consultato?

#### Viste Applicative = Sale di Lettura
- **Sala Lettura Bambini**: Vede solo libri per bambini
- **Sala Ricerca Aziendale**: Vede solo business ed economia
- **Sala Storia Locale**: Vede solo materiali regionali
- Ogni sala curata per il suo pubblico

#### Bibliotecari = Data Engineer
- Organizzano i materiali in arrivo
- Mantengono l'accuratezza del catalogo
- Aiutano gli utenti a trovare ciò di cui hanno bisogno
- Assicurano che il sistema funzioni senza intoppi

#### Utenti della Biblioteca = Utenti Aziendali
- Entrano e trovano ciò di cui hanno bisogno
- Non hanno bisogno di sapere da dove provengono i libri
- Possono navigare, cercare e analizzare
- Portano conoscenza per prendere decisioni

**Questa analogia aiuta a spiegare:**
- Perché abbiamo due livelli (ricezione vs. scaffalatura)
- Perché tracciamo le modifiche (nuove edizioni, informazioni aggiornate)
- Perché organizziamo per dimensioni (catalogo per argomenti)
- Perché creiamo viste speciali (sale di lettura)
- Perché conserviamo la storia (edizioni passate)

## Letture Consigliate

### Metodologia Kimball
- **Sito Ufficiale di Ralph Kimball**: [Kimball Group](https://www.kimballgroup.com/)
- **"The Data Warehouse Toolkit"** di Ralph Kimball (la guida definitiva)
- **Tecniche di Modellazione Dimensionale**: [Kimball Design Tips](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/)

### Risorse Wikipedia
- [Data Warehouse](https://it.wikipedia.org/wiki/Data_warehouse)
- [Modellazione Dimensionale](https://en.wikipedia.org/wiki/Dimensional_modeling)
- [Star Schema](https://en.wikipedia.org/wiki/Star_schema)
- [Extract, Transform, Load (ETL)](https://it.wikipedia.org/wiki/Extract,_transform,_load)
- [Business Intelligence](https://it.wikipedia.org/wiki/Business_intelligence)
- [Online Analytical Processing (OLAP)](https://it.wikipedia.org/wiki/OLAP)
- [Slowly Changing Dimension](https://en.wikipedia.org/wiki/Slowly_changing_dimension)
- [Chiave Surrogata](https://it.wikipedia.org/wiki/Chiave_surrogata)
- [Data Vault Modeling](https://en.wikipedia.org/wiki/Data_vault_modeling) (approccio alternativo)

### Standard e Best Practice del Settore
- **TDWI (The Data Warehousing Institute)**: [tdwi.org](https://tdwi.org/)
- **DAMA (Data Management Association)**: [dama.org](https://www.dama.org/)
- **Best Practice Microsoft SQL Server**: [Microsoft Docs](https://docs.microsoft.com/it-it/sql/)

### Risorse Accademiche e Professionali
- **Corporate Information Factory di Bill Inmon**: Architettura alternativa di data warehouse
- **Ricerca Data Warehouse Institute**: Tendenze e benchmark del settore
- **Ricerca Gartner**: Magic Quadrant per Piattaforme BI e Analytics

### Concetti Correlati
- [Master Data Management](https://it.wikipedia.org/wiki/Master_data_management)
- [Data Lake](https://en.wikipedia.org/wiki/Data_lake) (approccio complementare)
- [Data Mart](https://en.wikipedia.org/wiki/Data_mart) (sottoinsieme dipartimentale)
- [Data Governance](https://en.wikipedia.org/wiki/Data_governance)
- [Qualità dei Dati](https://it.wikipedia.org/wiki/Qualit%C3%A0_dei_dati)

---

## Glossario dei Termini Chiave

**Change Data Capture (CDC)**: Il processo di identificazione e tracciamento delle modifiche nei dati sorgente

**Dimensione**: Una categoria di informazioni che fornisce contesto (chi, cosa, quando, dove, perché)

**Fatto**: Una misurazione o metrica su un evento di business (quanto, quanti)

**Hash**: Un'impronta digitale unica calcolata dai dati per rilevare le modifiche

**Idempotente**: Un'operazione che produce lo stesso risultato indipendentemente da quante volte viene eseguita

**Metodologia Kimball**: Un approccio ampiamente utilizzato per progettare data warehouse basato sulla modellazione dimensionale

**Landing Zone**: Il primo livello dove i dati grezzi arrivano dai sistemi sorgente

**OLAP (Online Analytical Processing)**: Tecnologia per analizzare dati su più dimensioni

**Eliminazione Soft**: Contrassegnare i record come eliminati senza rimuoverli fisicamente

**Star Schema**: Un pattern di design con fatti al centro e dimensioni sui bordi

**Chiave Surrogata**: Un identificatore artificiale assegnato dal data warehouse

**Tracciamento Temporale**: Registrare quando i dati sono arrivati e cambiati nel tempo

---

**Versione Documento**: 1.0  
**Ultimo Aggiornamento**: 20 maggio 2026  
**Pubblico**: Utenti Aziendali, Manager, Stakeholder Non Tecnici  
**Metodologia**: Modellazione Dimensionale Kimball
