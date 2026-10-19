"""Rede DICOM: recepção, envio, consulta e recuperação.

No Horos esta parte é o DCMTK embutido e modificado — `storescp`/`dcmqrscp`
adaptados para gravar na base Core Data e consultá-la (pasta
Binaries/dcmtk-source/dcmqrdb), mais as classes DCMTKStoreSCU,
DCMTKQueryNode e DCMTKVerifySCU. Aqui o mesmo papel cabe ao pynetdicom,
uma implementação do protocolo DICOM em Python puro que roda igual no
Windows, sem compilar nada.
"""
