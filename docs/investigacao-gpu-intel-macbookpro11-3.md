# Investigação: GPU Intel Iris Pro no MacBookPro11,3

**Data:** 25 de setembro de 2026  
**Status:** diagnóstico provável; ativação ainda não testada

## Resumo

A causa mais provável de a Intel Iris Pro não aparecer no Debian é o firmware do Mac ocultá-la durante a inicialização do Linux. Há documentação específica para o modelo `MacBookPro11,3` descrevendo esse comportamento.

O projeto [`apple_set_os.efi`](https://github.com/0xbb/apple_set_os.efi) fornece um caminho conhecido: executá-lo antes do Linux para informar ao firmware que o sistema iniciado é macOS. O recurso equivalente também pode ser configurado pelo rEFInd.

## Evidências observadas

- O boot atual é UEFI → Debian/GRUB.
- A Intel não aparece no barramento PCI; portanto, o problema não é apenas falta de acesso dentro do Docker.
- O único dispositivo de renderização, `/dev/dri/renderD128`, pertence à NVIDIA.
- Não há `nomodeset` nem parâmetros desativando a Intel na configuração principal do GRUB.
- O módulo `apple_gmux` está carregado, mas o `i915` não está.

## Interpretação

Como a GPU Intel não está presente no barramento PCI, instalar ou carregar apenas um driver não deve resolver a situação. Primeiro é necessário fazê-la ser exposta pelo firmware durante o boot.

Isso ainda é uma hipótese fortemente respaldada pela documentação, não uma confirmação experimental: o boot não foi alterado e a máquina não foi reiniciada.

## Próximo teste recomendado

1. Criar uma entrada de boot separada para `apple_set_os.efi`, preservando a entrada atual.
2. Reiniciar e confirmar se a Intel passa a aparecer no PCI.
3. Verificar se o `i915` é carregado e quais dispositivos `/dev/dri` são criados.
4. Consultar os codecs e perfis VA-API disponíveis.
5. Só então configurar e medir uma transcodificação no Jellyfin.

O teste exige alteração no boot e reinicialização. Não foi executado nesta investigação.

## Jellyfin e aceleração esperada

Depois de habilitada, a Intel deve ser testada via VA-API usando o driver `i965`, com foco principalmente em H.264. Essa geração não oferece aceleração moderna de HEVC/AV1; o ganho real deve ser medido com uma transcodificação representativa.

Referência: [documentação de aceleração Intel do Jellyfin](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/intel/).

## Limitações de acesso

`sudo` exige senha nesta máquina. Por isso, não foi possível ler os registros protegidos do kernel nem o conteúdo da partição EFI. Essa limitação não altera as evidências já observadas, mas impede confirmar detalhes adicionais antes do teste de boot.

## Referências

- [`apple_set_os.efi`](https://github.com/0xbb/apple_set_os.efi)
- [Jellyfin — aceleração de hardware Intel](https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/intel/)
