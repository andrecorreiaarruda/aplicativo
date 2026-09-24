import '../../data/models/service_case.dart';

/// Textos do atendimento que mudam conforme a atividade: manutenção,
/// instalação ou desinstalação. Usados pelo formulário e pela ordem de
/// serviço, para que o campo tenha o mesmo nome nos dois lugares.
class ActivityCopy {
  const ActivityCopy({
    required this.openingSubtitle,
    required this.primaryFieldLabel,
    required this.primaryFieldHint,
    required this.primaryFieldValidation,
    required this.referenceLabel,
    required this.subsystemLabel,
    required this.initialNotesLabel,
    required this.impactLabel,
    required this.executionStepTitle,
    required this.executionSummaryLabel,
    required this.executionSummaryHint,
    required this.measurementsLabel,
    required this.measurementsHint,
    required this.deviationLabel,
    required this.progressEntryLabel,
    required this.progressEntryHint,
    required this.conclusionStepTitle,
    required this.conclusionSubtitle,
    required this.solutionLabel,
    required this.solutionHint,
    required this.solutionValidation,
    required this.validationLabel,
    required this.validationHint,
    required this.validationValidation,
    required this.confidenceLabel,
    required this.followUpLabel,
  });

  final String openingSubtitle;
  final String primaryFieldLabel;
  final String primaryFieldHint;
  final String primaryFieldValidation;
  final String referenceLabel;
  final String subsystemLabel;
  final String initialNotesLabel;
  final String impactLabel;
  final String executionStepTitle;
  final String executionSummaryLabel;
  final String executionSummaryHint;
  final String measurementsLabel;
  final String measurementsHint;
  final String deviationLabel;
  final String progressEntryLabel;
  final String progressEntryHint;
  final String conclusionStepTitle;
  final String conclusionSubtitle;
  final String solutionLabel;
  final String solutionHint;
  final String solutionValidation;
  final String validationLabel;
  final String validationHint;
  final String validationValidation;
  final String confidenceLabel;
  final String followUpLabel;

  static ActivityCopy forType(String type) {
    switch (type) {
      case ServiceActivityType.installation:
        return const ActivityCopy(
          openingSubtitle: 'Equipamento, escopo e condição inicial',
          primaryFieldLabel: 'Escopo da instalação',
          primaryFieldHint:
              'Descreva o equipamento, acessórios, responsabilidades e objetivo da instalação.',
          primaryFieldValidation: 'Informe o escopo da instalação.',
          referenceLabel: 'Projeto / OS / referência (opcional)',
          subsystemLabel: 'Conjunto / área principal (opcional)',
          initialNotesLabel: 'Condição inicial e pré-requisitos',
          impactLabel: 'Impacto durante a instalação',
          executionStepTitle: 'Execução',
          executionSummaryLabel: 'Etapas executadas',
          executionSummaryHint:
              'Montagem, posicionamento, conexões, energização e configurações realizadas.',
          measurementsLabel: 'Testes, medições e comissionamento',
          measurementsHint:
              'Registre valores, calibrações, testes funcionais e critérios de aceite.',
          deviationLabel: 'Pendências, desvios ou interferências',
          progressEntryLabel: 'Andamento do dia',
          progressEntryHint:
              'Ex.: Posicionada a gantry, instalados cabos e iniciada energização.',
          conclusionStepTitle: 'Conclusão',
          conclusionSubtitle: 'Comissionamento, aceite e liberação',
          solutionLabel: 'Configuração e serviços concluídos',
          solutionHint:
              'Resuma a montagem final, configurações, calibrações e condições de entrega.',
          solutionValidation: 'Informe o resultado final da instalação.',
          validationLabel: 'Testes de aceitação e liberação',
          validationHint:
              'Descreva testes aprovados, pendências e responsável pelo aceite.',
          validationValidation: 'Informe os testes finais da instalação.',
          confidenceLabel: 'Confiabilidade do registro',
          followUpLabel: 'Necessita retorno, treinamento ou etapa complementar',
        );
      case ServiceActivityType.deinstallation:
        return const ActivityCopy(
          openingSubtitle: 'Equipamento, escopo e condição antes da retirada',
          primaryFieldLabel: 'Escopo da desinstalação',
          primaryFieldHint:
              'Descreva o que será removido, embalado, transportado ou entregue.',
          primaryFieldValidation: 'Informe o escopo da desinstalação.',
          referenceLabel: 'Projeto / OS / destino (opcional)',
          subsystemLabel: 'Conjunto / área principal (opcional)',
          initialNotesLabel: 'Condição inicial e inventário preliminar',
          impactLabel: 'Impacto durante a retirada',
          executionStepTitle: 'Execução',
          executionSummaryLabel: 'Etapas de desligamento e desmontagem',
          executionSummaryHint:
              'Bloqueios, desconexões, desmontagem, identificação e embalagem realizadas.',
          measurementsLabel: 'Conferências, inventário e condição dos itens',
          measurementsHint:
              'Registre quantidades, integridade, volumes, acessórios e evidências.',
          deviationLabel: 'Avarias, faltas ou ocorrências',
          progressEntryLabel: 'Andamento do dia',
          progressEntryHint:
              'Ex.: Sistema desenergizado, detector removido e embalado no volume 03.',
          conclusionStepTitle: 'Conclusão',
          conclusionSubtitle: 'Embalagem, entrega e condição final',
          solutionLabel: 'Desmontagem, embalagem e destino final',
          solutionHint:
              'Resuma o que foi removido, identificado, embalado e entregue.',
          solutionValidation: 'Informe o resultado final da desinstalação.',
          validationLabel: 'Conferência final e entrega',
          validationHint:
              'Registre volumes, responsáveis, ressalvas e condição do local.',
          validationValidation: 'Informe a conferência final da desinstalação.',
          confidenceLabel: 'Confiabilidade do registro',
          followUpLabel: 'Necessita retorno, coleta ou etapa complementar',
        );
      default:
        return const ActivityCopy(
          openingSubtitle: 'Equipamento e falha relatada',
          primaryFieldLabel: 'Falha relatada',
          primaryFieldHint:
              'Descreva o relato do cliente, quando começou e o impacto percebido.',
          primaryFieldValidation: 'Informe a falha relatada.',
          referenceLabel: 'Código de erro (opcional)',
          subsystemLabel: 'Subsistema (opcional)',
          initialNotesLabel: 'Mensagem de erro / observações iniciais',
          impactLabel: 'Impacto operacional',
          executionStepTitle: 'Diagnóstico',
          executionSummaryLabel: 'Sintomas observados',
          executionSummaryHint:
              'Condições de ocorrência, intermitência, sequência e reprodução.',
          measurementsLabel: 'Testes e medições',
          measurementsHint:
              'Ação executada, valor medido, unidade e resultado.',
          deviationLabel: 'Causa-raiz ou hipótese atual',
          progressEntryLabel: 'Andamento técnico do dia',
          progressEntryHint:
              'Ex.: Coletados logs, inspecionadas fontes e reproduzida a falha após 20 minutos.',
          conclusionStepTitle: 'Conclusão',
          conclusionSubtitle: 'Solução, validação e retorno',
          solutionLabel: 'Solução aplicada',
          solutionHint:
              'Descreva peças, ajustes, configurações e sequência executada.',
          solutionValidation: 'A solução é obrigatória para concluir.',
          validationLabel: 'Validação final',
          validationHint:
              'Testes funcionais, ciclos, calibrações e critérios de aceite.',
          validationValidation: 'A validação é obrigatória para concluir.',
          confidenceLabel: 'Confiança da solução',
          followUpLabel: 'Necessita retorno ou acompanhamento',
        );
    }
  }
}
